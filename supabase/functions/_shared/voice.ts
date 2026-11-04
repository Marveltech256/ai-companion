import type { ApiDependencies } from './companion_api.ts';
import { ApiError,uuid } from './errors.ts';
import { boundedBody,cors,errorResponse,jsonBody } from './http.ts';

export interface AudioProvider {
  readonly speechMimeType?:string;
  transcribe(wav:Uint8Array,signal:AbortSignal):Promise<string>;
  speech(text:string,signal:AbortSignal):Promise<Uint8Array>;
}
export function validateWave(bytes:Uint8Array):void{
  if(bytes.length<3244||bytes.length>1920044)throw new ApiError(400,'invalid_audio','Record between a moment and one minute.');
  const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
  const marker=(offset:number)=>new TextDecoder().decode(bytes.slice(offset,offset+4));
  if(marker(0)!=='RIFF'||marker(8)!=='WAVE'||marker(12)!=='fmt '||marker(36)!=='data'||
    view.getUint32(4,true)!==bytes.length-8||view.getUint32(16,true)!==16||view.getUint16(20,true)!==1||
    view.getUint16(22,true)!==1||view.getUint32(24,true)!==16000||view.getUint32(28,true)!==32000||
    view.getUint16(32,true)!==2||view.getUint16(34,true)!==16||
    view.getUint32(40,true)!==bytes.length-44||(bytes.length-44)%2!==0)
    throw new ApiError(400,'invalid_audio','Please try recording again.');
}
export class OpenAIAudio implements AudioProvider {
  readonly speechMimeType='audio/mpeg';
  constructor(private key:string,private transcriptionModel:string,private speechModel:string,
    private voice:string,private fetcher=fetch){}
  private async post(path:string,body:BodyInit,signal:AbortSignal,json=false):Promise<Response>{
    if(!this.key||!(path==='transcriptions'?this.transcriptionModel:this.speechModel))
      throw new ApiError(503,'voice_not_configured','Voice is not connected yet.');
    const response=await this.fetcher(`https://api.openai.com/v1/audio/${path}`,{method:'POST',signal,
      headers:{Authorization:`Bearer ${this.key}`,...(json?{'Content-Type':'application/json'}:{})},body});
    if(!response.ok){await response.body?.cancel();throw new ApiError(503,'voice_unavailable','Voice interrupted. Please try again.');}
    return response;
  }
  async transcribe(wav:Uint8Array,signal:AbortSignal):Promise<string>{
    const form=new FormData();
    form.set('file',new Blob([new Uint8Array(wav).buffer],{type:'audio/wav'}),'voice.wav');
    form.set('model',this.transcriptionModel);form.set('response_format','json');
    const response=await this.post('transcriptions',form,signal);
    const result=JSON.parse(new TextDecoder().decode(await boundedBody(response,65536)));
    if(typeof result.text!=='string'||!result.text.trim()||result.text.length>12000)
      throw new ApiError(400,'no_speech','I could not hear clear speech. Please try again.');
    return result.text.trim();
  }
  async speech(text:string,signal:AbortSignal):Promise<Uint8Array>{
    if(!['alloy','ash','ballad','coral','echo','fable','onyx','nova','sage','shimmer','verse','marin','cedar'].includes(this.voice))
      throw new ApiError(503,'voice_not_configured','Voice is not connected yet.');
    const response=await this.post('speech',JSON.stringify({model:this.speechModel,input:text,
      voice:this.voice,response_format:'mp3'}),signal,true);
    const bytes=await boundedBody(response,4*1024*1024);
    if(!bytes.length)throw new ApiError(503,'voice_unavailable','Voice interrupted. Please try again.');
    return bytes;
  }
}
export function createVoiceApi(deps:ApiDependencies & {audio:AudioProvider}){
  return async(request:Request):Promise<Response>=>{
    let headers=new Headers({'Cache-Control':'no-store'});
    try{
      headers=cors(request,deps.origins);
      if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
      if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','POST is required.');
      const identity=await deps.verify(request);
      await deps.eligible?.(identity.uid);
      await deps.friendEligible?.(identity.uid);
      const action=new URL(request.url).searchParams.get('action');
      const signal=AbortSignal.any([request.signal,AbortSignal.timeout(60000)]);
      if(action==='transcribe'){
        if(request.headers.get('content-type')?.split(';')[0]!=='audio/wav')
          throw new ApiError(415,'invalid_audio','WAV audio is required.');
        const bytes=await boundedBody(request,1920044);validateWave(bytes);
        await deps.db.rpc('morrow_access_voice',{p_owner:identity.uid});
        const text=await deps.audio.transcribe(bytes,signal);
        return Response.json({text},{headers});
      }
      if(action==='speech'){
        const body=await jsonBody(request),message=uuid(body.message_id);
        const part=body.part??0;
        if(!Number.isInteger(part)||(part as number)<0||(part as number)>11)
          throw new ApiError(400,'invalid_input','Invalid voice segment.');
        const {content}=await deps.db.rpc<{content:string}>('morrow_voice_message',{
          p_owner:identity.uid,p_message:message});
        const chunkSize=deps.audio.speechMimeType==='audio/wav'?1000:3000;
        const characters=Array.from(content),parts=Math.ceil(characters.length/chunkSize);
        if((part as number)>=parts)throw new ApiError(400,'invalid_input','Invalid voice segment.');
        await deps.db.rpc('morrow_access_voice',{p_owner:identity.uid});
        const bytes=await deps.audio.speech(characters.slice((part as number)*chunkSize,((part as number)+1)*chunkSize).join(''),signal);
        headers.set('Content-Type',deps.audio.speechMimeType??'audio/mpeg');headers.set('X-Morrow-Audio-Parts',String(parts));
        headers.set('Access-Control-Expose-Headers','X-Morrow-Audio-Parts');
        return new Response(new Uint8Array(bytes).buffer,{headers});
      }
      throw new ApiError(400,'unknown_action','Unknown voice action.');
    }catch(error){return errorResponse(error,headers);}
  };
}
