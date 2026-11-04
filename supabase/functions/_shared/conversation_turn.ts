import type { ApiDependencies } from './companion_api.ts';
import type { AiProvider, CompanionConfig, HistoryMessage, MemoryFact, Observations } from './openai.ts';
import { ApiError, publicError, requiredString, uuid } from './errors.ts';
import { cors, errorResponse, jsonBody } from './http.ts';
import type { CompanionContext } from './companion_context.ts';

interface Claim {
  status:string; lease:string; text?:string; companion:CompanionConfig;
  history:HistoryMessage[];consent_version:number;request_id?:string;
}
export interface TurnDependencies extends ApiDependencies {
  ai:AiProvider;
  memories?(uid:string,companion:string,query:string):Promise<MemoryFact[]>;
  personalization?(uid:string,companion:string):Promise<Observations|null>;
  context?(uid:string,companion:string,query:string,conversation:string):Promise<CompanionContext>;
  completed?(uid:string,request:string):Promise<void>;
  defer?(work:Promise<void>):void;
}

export function createConversationTurn(deps:TurnDependencies){
  return async(request:Request):Promise<Response>=>{
    let headers=new Headers({'Cache-Control':'no-store'});
    try{
      headers=cors(request,deps.origins);
      if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
      if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','POST is required.');
      const identity=await deps.verify(request),body=await jsonBody(request);
      const conversation=uuid(body.conversation_id),requestId=uuid(body.request_id);
      if(body.initiate!==undefined&&typeof body.initiate!=='boolean')throw new ApiError(400,'invalid_input','Invalid conversation operation.');
      const greeting=body.initiate===true;
      await deps.eligible?.(identity.uid);
      await deps.friendEligible?.(identity.uid);
      const content=greeting?'':requiredString(body.content,'message',12000);
      const claim=await deps.db.rpc<Claim>(greeting?'morrow_access_begin_greeting':'morrow_access_begin_turn',{
        p_owner:identity.uid,p_conversation:conversation,p_request:requestId,...(greeting?{}:{p_content:content})});
      const claimedRequest=claim.request_id??requestId;
      const encoder=new TextEncoder(),abort=new AbortController();
      const signal=AbortSignal.any([abort.signal,request.signal,AbortSignal.timeout(90000)]);
      let cancelled=false;
      headers.set('Content-Type','text/event-stream; charset=utf-8');
      headers.set('X-Accel-Buffering','no');
      const stream=new ReadableStream<Uint8Array>({
        async start(controller){
          const send=(data:Record<string,unknown>)=>{
            if(!cancelled)controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`));
          };
          const heartbeat=setInterval(()=>{
            if(!cancelled)controller.enqueue(encoder.encode(': keepalive\n\n'));
          },15000);
          try{
            send({type:'meta',request_id:requestId});
            if(claim.status==='completed'){
              send({type:'delta',text:claim.text??''});
            }else{
              // Independent owned reads share the same verified identity. Run
              // them together before the existing single generation request.
              const [context,observations]=await Promise.all([
                deps.context?deps.context(identity.uid,claim.companion.id,content,conversation):undefined,
                claim.companion.learning_enabled && deps.personalization
                  ?deps.personalization(identity.uid,claim.companion.id):null,
              ]);
              const memories=!context && claim.companion.memory_enabled && deps.memories
                ?await deps.memories(identity.uid,claim.companion.id,content):[];
              let text='';
              for await(const delta of deps.ai.reply({companion:claim.companion,
                history:claim.history,memories,observations,context,purpose:greeting?'greeting':'reply'},signal)){
                text+=delta;
                if(text.length>12000)throw new ApiError(503,'reply_too_long','Reply interrupted. Please retry.');
                send({type:'delta',text:delta});
              }
              if(!text.trim())throw new Error('Empty provider output');
              await deps.db.rpc('morrow_complete_turn',{
                p_owner:identity.uid,p_request:claimedRequest,p_lease:claim.lease,p_content:text});
              if(deps.completed && !greeting){
                const work=deps.completed(identity.uid,claimedRequest).catch(()=>{
                  // No transcript, token, or private provider response in logs.
                  console.error('memory_processing_failed');
                });
                if(deps.defer)deps.defer(work);else await work;
                if(context?.first_meeting.name_question_asked && !context.identity.preferred_name && content.length<=160)await work;
              }
            }
            send({type:'done',request_id:requestId});
          }catch(error){
            if(claim.status!=='completed')await deps.db.rpc('morrow_fail_turn',{
              p_owner:identity.uid,p_request:claimedRequest,p_lease:claim.lease}).catch(()=>{});
            const safe=publicError(error);
            send({type:'error',code:safe.code,message:safe.message});
          }finally{
            clearInterval(heartbeat);
            if(!cancelled)controller.close();
          }
        },
        cancel(){cancelled=true;abort.abort();},
      });
      return new Response(stream,{headers});
    }catch(error){return errorResponse(error,headers);}
  };
}
