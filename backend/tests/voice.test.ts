import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database,rpc } from './database.ts';
import { createVoiceApi,validateWave,OpenAIAudio } from '../../supabase/functions/_shared/voice.ts';

function wave():Uint8Array{
  const bytes=new Uint8Array(6444),v=new DataView(bytes.buffer),encoder=new TextEncoder();
  for(const [offset,s] of [[0,'RIFF'],[8,'WAVE'],[12,'fmt '],[36,'data']] as const)bytes.set(encoder.encode(s),offset);
  v.setUint32(4,bytes.length-8,true);v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,1,true);
  v.setUint32(24,16000,true);v.setUint32(28,32000,true);v.setUint16(32,2,true);v.setUint16(34,16,true);v.setUint32(40,6400,true);
  return bytes;
}
test('voice enforces consent, ownership, format, and persisted assistant-only speech',async()=>{
  const db=await database();
  try{
    await rpc(db,'morrow_bootstrap',{p_owner:'alice'});
    const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:'alice',p_name:'Lumi',p_style:'Playful',
      p_interests:[],p_response_length:.5,p_memory_enabled:false,p_retention_days:null});
    await assert.rejects(rpc(db,'morrow_authorize_voice',{p_owner:'alice'}),/consent_required/);
    await rpc(db,'morrow_set_voice',{p_owner:'alice',p_companion:companion.id,p_enabled:true});
    const {conversation}=await rpc<any>(db,'morrow_create_conversation',{p_owner:'alice',p_companion:companion.id});
    const request=randomUUID(),claim=await rpc<any>(db,'morrow_begin_turn',{
      p_owner:'alice',p_conversation:conversation.id,p_request:request,p_content:'I enjoy cycling.'});
    await rpc(db,'morrow_complete_turn',{p_owner:'alice',p_request:request,p_lease:claim.lease,p_content:'Where do you like cycling?'});
    const messages=await rpc<any>(db,'morrow_messages',{p_owner:'alice',p_conversation:conversation.id});
    const assistant=messages.messages.find((m:any)=>m.role==='assistant');
    await assert.rejects(rpc(db,'morrow_voice_message',{p_owner:'bob',p_message:assistant.id}),/not_found/);
    await assert.rejects(rpc(db,'morrow_voice_message',{p_owner:'alice',p_message:messages.messages[0].id}),/not_found/);
    assert.equal((await rpc<any>(db,'morrow_voice_message',{p_owner:'alice',p_message:assistant.id})).content,assistant.content);
    await rpc(db,'morrow_set_voice',{p_owner:'alice',p_companion:companion.id,p_enabled:false});
    await assert.rejects(rpc(db,'morrow_voice_message',{p_owner:'alice',p_message:assistant.id}),/not_found/);
    validateWave(wave());const invalid=wave();invalid[24]=0;assert.throws(()=>validateWave(invalid));
  }finally{await db.close();}
});
test('voice API authorizes before calling the provider and never speaks client-supplied text',async()=>{
  let spoken='',transcriptions=0;
  const handler=createVoiceApi({origins:[],verify:async()=>({uid:'alice'}),
    db:{rpc:async<T>(name:string)=>((name==='morrow_voice_message'?{content:'Saved assistant reply'}:{ok:true}) as T)},
    audio:{transcribe:async()=>{transcriptions++;return 'I enjoy cycling.';},speech:async(text)=>{spoken=text;return new Uint8Array([1,2]);}}});
  const response=await handler(new Request('https://local.test?action=speech',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({message_id:randomUUID(),text:'Injected speech'})}));
  assert.equal(response.status,200);assert.equal(spoken,'Saved assistant reply');
  assert.equal(response.headers.get('Cache-Control'),'no-store');
  const bad=await handler(new Request('https://local.test?action=transcribe',{method:'POST',headers:{'Content-Type':'audio/wav'},body:new Uint8Array(44)}));
  assert.equal(bad.status,400);assert.equal(transcriptions,0);
});
test('OpenAI audio uses the configured models and server credential',async()=>{
  const requests:{url:string;init:RequestInit}[]=[];
  const provider=new OpenAIAudio('server-secret','configured-transcription','configured-speech','marin',async(url,init)=>{
    requests.push({url:String(url),init:init!});
    return String(url).endsWith('transcriptions')?Response.json({text:'Hello'}):new Response(new Uint8Array([1,2]));
  });
  assert.equal(await provider.transcribe(wave(),new AbortController().signal),'Hello');
  await provider.speech('Hello',new AbortController().signal);
  assert.equal((requests[0].init.body as FormData).get('model'),'configured-transcription');
  assert.equal(JSON.parse(requests[1].init.body as string).model,'configured-speech');
  assert.equal((requests[1].init.headers as any).Authorization,'Bearer server-secret');
});
