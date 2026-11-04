import {test} from 'node:test';
import assert from 'node:assert/strict';
import {database,rpc} from './database.ts';
import {GeminiAudio} from '../../supabase/functions/_shared/gemini_audio.ts';
import {audioCapabilities,createAudioProvider} from '../../supabase/functions/_shared/audio_factory.ts';
import {companionInstructions} from '../../supabase/functions/_shared/openai.ts';

test('friend mode requires affirmative consent and preserves ownership, timezone choice and reply preference',async()=>{
 const db=await database();try{
  for(const owner of ['alice','bobby']){
   await rpc(db,'morrow_bootstrap',{p_owner:owner});
   await rpc(db,'morrow_save_named_profile',{p_owner:owner,p_username:owner,p_preferred_name:owner,p_display_name:null,p_timezone:null,p_language:null,p_location:null});
   await rpc(db,'morrow_save_friend_introduction',{p_owner:owner,p_age_group:'25_34',p_language:'en',p_timezone:'Africa/Kampala',p_automatic:true});
  }
  const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:'alice',p_name:'Lumi',p_style:'Reflective',p_interests:[],p_response_length:0,p_memory_enabled:false,p_retention_days:null});
  await assert.rejects(rpc(db,'morrow_require_friend_mode',{p_owner:'alice'}),/personal_companion_required/);
  await assert.rejects(rpc(db,'morrow_activate_friend_mode',{p_owner:'alice',p_companion:companion.id,p_consent:false}),/consent_required/);
  const before=await rpc<any>(db,'morrow_bootstrap',{p_owner:'alice'});assert.equal(before.companion.memory_enabled,false);assert.equal(before.companion.learning_enabled,false);
  await assert.rejects(rpc(db,'morrow_activate_friend_mode',{p_owner:'bobby',p_companion:companion.id,p_consent:true}),/not_found/);
  const active=await rpc<any>(db,'morrow_activate_friend_mode',{p_owner:'alice',p_companion:companion.id,p_consent:true});
  assert.equal(active.companion.memory_enabled,true);assert.equal(active.companion.learning_enabled,true);
  assert.deepEqual(await rpc(db,'morrow_require_friend_mode',{p_owner:'alice'}),{ok:true});
  const manual=await rpc<any>(db,'morrow_save_timezone',{p_owner:'alice',p_timezone:'Europe/London',p_automatic:false});
  assert.equal(manual.profile.timezone,'Europe/London');assert.equal(manual.profile.timezone_automatic,false);
  await assert.rejects(rpc(db,'morrow_save_timezone',{p_owner:'alice',p_timezone:'not/a/zone',p_automatic:true}),/invalid_input/);
  const mode=await rpc<any>(db,'morrow_reply_mode',{p_owner:'alice',p_mode:'voice'});assert.equal(mode.profile.reply_mode,'voice');
  assert.equal((await rpc<any>(db,'morrow_bootstrap',{p_owner:'bobby'})).profile.reply_mode,'text');
  await assert.rejects(rpc(db,'morrow_reply_mode',{p_owner:'alice',p_mode:'invalid'}),/invalid_input/);
 }finally{await db.close();}
});

test('Gemini transcribes original audio without translating or executing spoken instructions, and returns WAV speech',async()=>{
 const calls:any[]=[];const wav=new Uint8Array(100);wav.set(new TextEncoder().encode('RIFF'));wav.set(new TextEncoder().encode('WAVE'),8);
 const provider=new GeminiAudio('server-secret','asr-model','tts-model','Kore',async(url,init)=>{
  const body=JSON.parse(init!.body as string);calls.push({url:String(url),headers:new Headers(init?.headers),body});
  if(String(url).endsWith('/interactions'))return Response.json({status:'completed',steps:[{type:'model_output',content:[{type:'audio',data:btoa(String.fromCharCode(...wav))}]}]});
  return Response.json({candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify({transcript:'Call Sam at 7:30, not Alex.'})}]}}]});
 });
 assert.equal(await provider.transcribe(new Uint8Array([1,2,3]),AbortSignal.timeout(1000)),'Call Sam at 7:30, not Alex.');
 assert.equal(calls[0].headers.get('x-goog-api-key'),'server-secret');assert.ok(!calls[0].url.includes('secret'));
 assert.ok(calls[0].body.systemInstruction.parts[0].text.includes('Do not summarize, translate'));
 assert.equal(calls[0].body.contents[0].parts[0].inlineData.data,'AQID');
 assert.deepEqual(await provider.speech('Exactly this saved reply.',AbortSignal.timeout(1000)),wav);
 assert.equal(calls[1].body.store,false);assert.equal(calls[1].body.response_format.mime_type,'audio/wav');
 assert.equal(calls[1].body.input[0].content[0].text,'Exactly this saved reply.');
 const empty=new GeminiAudio('key','asr','tts','Kore',async()=>Response.json({candidates:[{finishReason:'STOP',content:{parts:[{text:'{"transcript":""}'}]}}]}));
 await assert.rejects(empty.transcribe(wav,AbortSignal.timeout(1000)),/No clear speech/);
 const bad=new GeminiAudio('key','asr','tts','Kore',async()=>Response.json({status:'completed',steps:[{type:'model_output',content:[{type:'audio',data:'invalid'}]}]}));
 await assert.rejects(bad.speech('Test',AbortSignal.timeout(1000)),/Voice could not complete/);
});

test('voice capabilities match configured operations and natural tone stays provisional rather than a diagnosis',async()=>{
 const values:Record<string,string>={GEMINI_API_KEY:'key',GEMINI_TRANSCRIPTION_MODEL:'asr',GEMINI_SPEECH_MODEL:'tts'};
 assert.deepEqual(audioCapabilities(n=>values[n]),{welcome_audio:true,transcription:true});
 assert.equal(createAudioProvider(n=>values[n]).speechMimeType,'audio/wav');
 assert.deepEqual(audioCapabilities(n=>n==='GEMINI_BACKUP_ENABLED'?'false':values[n]),{welcome_audio:false,transcription:false});
 const instructions=companionInstructions({id:'c',name:'Lumi',communication_style:'Playful',response_length:0,memory_enabled:true},[]);
 assert.ok(instructions.includes('tentative'));assert.ok(instructions.includes('never a diagnosis'));
 assert.ok(instructions.includes('not generic search answers'));assert.ok(!instructions.includes('Your selected style is'));
});
