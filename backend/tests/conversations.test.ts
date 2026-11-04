import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database,rpc } from './database.ts';
import { createConversationTurn } from '../../supabase/functions/_shared/conversation_turn.ts';
import { boundedHistory,OpenAIResponses } from '../../supabase/functions/_shared/openai.ts';
import type {CompanionContext} from '../../supabase/functions/_shared/companion_context.ts';

test('context and personalisation load together before one unchanged generation request',async()=>{
 let contextStarted=false,patternsStarted=false,generations=0,completions=0;
 let releaseContext!:(context:CompanionContext)=>void,releasePatterns!:(value:null)=>void;
 const context=new Promise<CompanionContext>(resolve=>releaseContext=resolve),patterns=new Promise<null>(resolve=>releasePatterns=resolve);
 const handler=createConversationTurn({origins:[],verify:async()=>({uid:'alice'}),
  db:{rpc:async<T>(name:string)=>{if(name==='morrow_complete_turn')completions++;
   return (name==='morrow_access_begin_turn'?{status:'running',lease:randomUUID(),
    companion:{id:randomUUID(),name:'Lumi',communication_style:'Gentle & warm',memory_enabled:true,learning_enabled:true,response_length:.5},history:[{role:'user',content:'Hello'}]}:{ok:true}) as T;}},
  context:async()=>{contextStarted=true;return context;},
  personalization:async()=>{patternsStarted=true;return patterns;},
  ai:{async *reply(input){generations++;assert.equal(input.observations,null);yield 'Hello there.';}}});
 const response=await handler(new Request('https://local.test',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({conversation_id:randomUUID(),request_id:randomUUID(),content:'Hello'})}));
 const output=response.text();
 try{assert.equal(contextStarted,true);assert.equal(patternsStarted,true);assert.equal(generations,0);}
 finally{releaseContext({identity:{preferred_name:null},clock:{utc:'2026-11-03T00:00:00Z',timezone:null,local:null,local_date:null},
  first_meeting:{introduced:true,name_question_asked:false},memories:[],previous_discussions:[]});releasePatterns(null);}
 assert.match(await output,/"done"/);assert.equal(generations,1);assert.equal(completions,1);
});

test('turns are owned, idempotent, retryable, and lease-protected',async()=>{
  const db=await database();
  try{
    for(const owner of ['alice','bob'])await rpc(db,'morrow_bootstrap',{p_owner:owner});
    const saved=await rpc<Record<string,any>>(db,'morrow_save_companion',{
      p_owner:'alice',p_name:'Lumi',p_style:'Playful',p_interests:[],p_response_length:.5,
      p_memory_enabled:true,p_retention_days:null});
    await assert.rejects(rpc(db,'morrow_create_conversation',{
      p_owner:'bob',p_companion:saved.companion.id}),/not_found/);
    const created=await rpc<Record<string,any>>(db,'morrow_create_conversation',{
      p_owner:'alice',p_companion:saved.companion.id});
    const same=await rpc<Record<string,any>>(db,'morrow_create_conversation',{
      p_owner:'alice',p_companion:saved.companion.id,p_id:created.conversation.id});
    assert.equal(same.conversation.id,created.conversation.id);
    const args={p_owner:'alice',p_conversation:created.conversation.id,
      p_request:randomUUID(),p_content:'I enjoy painting.'};
    const claim=await rpc<Record<string,any>>(db,'morrow_begin_turn',args);
    await assert.rejects(rpc(db,'morrow_begin_turn',args),/turn_busy/);
    await assert.rejects(rpc(db,'morrow_messages',{
      p_owner:'bob',p_conversation:created.conversation.id}),/not_found/);
    await rpc(db,'morrow_fail_turn',{p_owner:'alice',p_request:args.p_request,p_lease:claim.lease});
    const retry=await rpc<Record<string,any>>(db,'morrow_begin_turn',args);
    assert.notEqual(retry.lease,claim.lease);
    await assert.rejects(rpc(db,'morrow_complete_turn',{
      p_owner:'alice',p_request:args.p_request,p_lease:claim.lease,p_content:'Late reply'}),/stale_turn/);
    await rpc(db,'morrow_complete_turn',{
      p_owner:'alice',p_request:args.p_request,p_lease:retry.lease,p_content:'What do you enjoy painting?'});
    const cached=await rpc<Record<string,any>>(db,'morrow_begin_turn',args);
    assert.equal(cached.status,'completed');assert.equal(cached.text,'What do you enjoy painting?');
    await assert.rejects(rpc(db,'morrow_begin_turn',{...args,p_content:'Different message'}),/request_conflict/);
    const messages=await rpc<Record<string,any>>(db,'morrow_messages',{
      p_owner:'alice',p_conversation:created.conversation.id});
    assert.equal(messages.messages.length,2);
  }finally{await db.close();}
});

test('a stream is marked done only after the reply has persisted',async()=>{
  const calls:string[]=[];
  const handler=createConversationTurn({origins:[],verify:async()=>({uid:'alice'}),
    db:{rpc:async<T>(name:string)=>{
      calls.push(name);
      return (name==='morrow_access_begin_turn'?{status:'running',lease:randomUUID(),
        companion:{id:randomUUID(),name:'Lumi',communication_style:'Gentle & warm',memory_enabled:false,response_length:.5},
        history:[{role:'user',content:'Hello'}]}:{ok:true}) as T;
    }},ai:{async *reply(){yield 'Hello ';yield 'there.';}}});
  const response=await handler(new Request('https://local.test',{method:'POST',
    headers:{'Content-Type':'application/json'},body:JSON.stringify({conversation_id:randomUUID(),request_id:randomUUID(),content:'Hello'})}));
  const output=await response.text();
  assert.match(output,/'done'|"done"/);assert.match(output,/there\./);
  assert.ok(calls.includes('morrow_complete_turn'));assert.ok(!calls.includes('morrow_fail_turn'));
});

test('OpenAI requests are bounded, secret-backed, stateless and parse deltas',async()=>{
  let input:any;
  const provider=new OpenAIResponses('server-secret','configured-model','configured-model',async(_url,init)=>{
    input=JSON.parse(init!.body as string);
    return new Response('data: {"type":"response.output_text.delta","delta":"Hello"}\n\n'
      +'data: {"type":"response.completed"}\n\n');
  });
  let text='';
  for await(const delta of provider.reply({companion:{id:randomUUID(),name:'Lumi',communication_style:'Playful',
    memory_enabled:false,response_length:.5},history:[{role:'user',content:'Hi'}],memories:[{category:'people',content:'SECRET FACT'}]},new AbortController().signal))text+=delta;
  assert.equal(text,'Hello');assert.equal(input.store,false);assert.equal(input.stream,true);
  assert.ok(!input.instructions.includes('SECRET FACT'));
  const history=boundedHistory(Array.from({length:100},()=>({role:'user' as const,content:'x'.repeat(2000)})));
  assert.ok(history.reduce((sum,m)=>sum+m.content.length,0)<=18000);
});
