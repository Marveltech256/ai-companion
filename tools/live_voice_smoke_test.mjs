// Fictional account and synthetic audio; no personal recordings or credentials logged.
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {serverEvents} from '../supabase/functions/_shared/openai.ts';
const config=JSON.parse(await readFile('config/development.json','utf8'));
let user,stage='signup';const results=[];
async function firebase(action,body){const r=await fetch(`https://identitytoolkit.googleapis.com/v1/${action}?key=${config.FIREBASE_ANDROID_API_KEY}`,{
 method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});if(!r.ok)throw new Error(`Firebase HTTP ${r.status}`);return r.json();}
async function request(endpoint,body,type='application/json'){
 return fetch(`${config.SUPABASE_URL}/functions/v1/${endpoint}`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,
  Authorization:`Bearer ${user.token}`,'Content-Type':type},body:type==='application/json'?JSON.stringify(body):body,signal:AbortSignal.timeout(100000)});
}
async function api(body,endpoint='companion-api',status=200){const r=await request(endpoint,body),value=await r.json();assert.equal(r.status,status,`${endpoint}: ${value.code??r.status}`);return value;}
function wave16k(bytes){
 const input=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);let data,rate,channels,bits;
 for(let i=12;i+8<=bytes.length;){const size=input.getUint32(i+4,true),name=new TextDecoder().decode(bytes.slice(i,i+4));
  if(name==='fmt '){channels=input.getUint16(i+10,true);rate=input.getUint32(i+12,true);bits=input.getUint16(i+22,true);}
  if(name==='data')data=bytes.slice(i+8,i+8+size);i+=8+size+(size%2);
 }
 assert.equal(channels,1);assert.equal(bits,16);assert.ok(rate&&data);
 const samples=new DataView(data.buffer,data.byteOffset,data.byteLength),count=Math.floor(data.length/2*16000/rate);
 const wav=new Uint8Array(44+count*2),out=new DataView(wav.buffer),encoder=new TextEncoder();
 for(const [offset,text] of [[0,'RIFF'],[8,'WAVE'],[12,'fmt '],[36,'data']])wav.set(encoder.encode(text),offset);
 out.setUint32(4,wav.length-8,true);out.setUint32(16,16,true);out.setUint16(20,1,true);out.setUint16(22,1,true);
 out.setUint32(24,16000,true);out.setUint32(28,32000,true);out.setUint16(32,2,true);out.setUint16(34,16,true);out.setUint32(40,count*2,true);
 for(let n=0;n<count;n++){const pos=n*rate/16000,index=Math.floor(pos),next=Math.min(index+1,data.length/2-1),fraction=pos-index;
  out.setInt16(44+n*2,Math.round(samples.getInt16(index*2,true)*(1-fraction)+samples.getInt16(next*2,true)*fraction),true);}
 return wav;
}
const passed=check=>{results.push({check,passed:true});console.log(check);};
try{
 const suffix=randomBytes(9).toString('hex'),account=await firebase('accounts:signUp',{email:`voice-${suffix}@example.invalid`,password:`Aa!9${randomBytes(24).toString('base64url')}`,returnSecureToken:true});
 user={uid:account.localId,token:account.idToken};await api({action:'bootstrap'});
 await api({action:'save_personal_profile',username:`v_${suffix}`,preferred_name:'Voice Tester',display_name:null,timezone:'Africa/Kampala',language:'en',general_location:null});
 await api({action:'save_introduction',age_group:'25_34',language:'en',timezone:'Africa/Kampala',timezone_automatic:true});
 const {companion}=await api({action:'save_companion',name:'Lumi',style:'Gentle & warm',interests:[],response_length:.5,memory_enabled:false,retention_days:null});
 const before=await request('voice?action=transcribe',wave16k(new Uint8Array(await readFile('.cache/voice-synthetic-output.wav'))),'audio/wav');
 assert.equal(before.status,403);assert.equal((await before.json()).code,'personal_companion_required');
 await api({action:'activate_friend_mode',companion_id:companion.id,consent:true});
 await api({action:'set_voice',companion_id:companion.id,enabled:true});
 const {profile}=await api({action:'set_reply_mode',mode:'voice'});assert.equal(profile.reply_mode,'voice');
 const state=await api({action:'bootstrap'});assert.equal(state.capabilities.transcription,true);assert.equal(state.capabilities.welcome_audio,true);
 passed('Voice input is blocked before friend consent; activation and voice reply preference persist');
 stage='deployed transcription';
 const r=await request('voice?action=transcribe',wave16k(new Uint8Array(await readFile('.cache/voice-synthetic-output.wav'))),'audio/wav');
 const transcript=await r.json();assert.equal(r.status,200,transcript.code);assert.match(transcript.text,/friday/i);assert.match(transcript.text,/sam/i);assert.match(transcript.text,/not alex/i);
 passed('Real recorded-audio endpoint preserves the synthetic name, time and negation');
 stage='reviewed text and saved answer';
 const {conversation}=await api({action:'create_conversation',companion_id:companion.id,title:'Fictional voice verification'});
 const content=transcript.text+' Please answer in one short sentence without claiming any reminder has been scheduled.';
 const turn=await request('conversation-turn',{conversation_id:conversation.id,request_id:randomUUID(),content});let done=false;
 for await(const event of serverEvents(turn.body)){if(event.type==='error')throw new Error(event.code);if(event.type==='done')done=true;}
 assert.ok(done);const {messages}=await api({action:'messages',conversation_id:conversation.id});
 assert.equal(messages.find(m=>m.role==='user').content,content);const answer=messages.find(m=>m.role==='assistant');assert.ok(answer.content);
 passed('Confirmed transcript and complete text reply are saved in the shared conversation');
 stage='deployed speech playback payload';
 const spoken=await request('voice?action=speech',{message_id:answer.id,part:0});assert.equal(spoken.status,200);
 assert.ok(spoken.headers.get('Content-Type')?.startsWith('audio/wav'));
 const audio=new Uint8Array(await spoken.arrayBuffer());assert.equal(new TextDecoder().decode(audio.slice(0,4)),'RIFF');assert.ok(audio.length>1000);
 await writeFile('.cache/live-voice-answer.wav',audio);
 await api({message_id:randomUUID(),part:0},'voice?action=speech',404);
 passed('Real speech is generated only from an owned saved assistant reply and returned as playable WAV');
}catch(error){results.push({check:stage,passed:false,error:error.message});process.exitCode=1;}
finally{
 if(user){try{
  await api({action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'},'privacy',202);
  let complete=false;for(let i=0;i<20;i++){const status=await api({action:'erasure_status'},'privacy');if(status.status==='complete'){complete=true;break;}await new Promise(r=>setTimeout(r,1000));}
  assert.ok(complete);passed('Fictional voice-test identity and its data erased');
 }catch(error){results.push({check:'cleanup',passed:false,test_uid:user.uid,error:error.message});process.exitCode=1;}}
 const report={checked_at_utc:new Date().toISOString(),results};await writeFile('.cache/live-voice-verification.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
}
