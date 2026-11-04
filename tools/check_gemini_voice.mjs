// Fictional provider round-trip only. No keys or provider payloads are logged.
import {createRequire} from 'node:module';
import path from 'node:path';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {GeminiAudio} from '../supabase/functions/_shared/gemini_audio.ts';
const require=createRequire(import.meta.url),cli=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount}=require(path.join(cli,'auth.js')),{requireAuth}=require(path.join(cli,'requireAuth.js'));
const {Client}=require(path.join(cli,'apiv2.js')),{logger}=require(path.join(cli,'logger.js'));
logger.level='error';for(const t of logger.transports??[])t.level='error';
let stage='authenticate';const statuses=[];
try{
 const project='ai-personal-companion',account=getGlobalDefaultAccount();
 await requireAuth({project,projectId:project,nonInteractive:true,...(account?{user:account.user,tokens:account.tokens}:{})});
 const api=new Client({urlPrefix:'https://apikeys.googleapis.com',apiVersion:'v2',auth:true});
 const key=(await api.get('/projects/700569985311/locations/global/keys/ai-companion-gemini-server/keyString',{skipLog:{resBody:true}})).body.keyString;
 const model=process.env.GEMINI_VOICE_TEST_MODEL||'gemini-3.8-flash-lite-tts';
 const transcriptionModel=process.env.GEMINI_TRANSCRIPTION_TEST_MODEL||'gemini-3.5-flash-lite';
 const audio=new GeminiAudio(key,transcriptionModel,model,'Kore',async(url,init)=>{
  const response=await fetch(url,init);statuses.push({stage,http_status:response.status});return response;
 });
 stage='speech';const bytes=process.env.GEMINI_AUDIO_TEST_REUSE==='true'?new Uint8Array(await fs.readFile('.cache/voice-synthetic-output.wav')):await audio.speech('This is a voice test. On Friday at seven thirty, call Sam, not Alex.',AbortSignal.timeout(60000));
 await fs.writeFile('.cache/voice-synthetic-output.wav',bytes);
 stage='transcription';const text=await audio.transcribe(bytes,AbortSignal.timeout(60000));
 assert.match(text,/friday/i);assert.match(text,/sam/i);assert.match(text,/not alex/i);
 const report={checked_at_utc:new Date().toISOString(),speech_model:model,transcription_model:transcriptionModel,
  generated_audio_bytes:bytes.length,synthetic_transcript:text,statuses,passed:true};
 await fs.writeFile('.cache/gemini-voice-verification.json',JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
}catch(error){console.error(JSON.stringify({stage,statuses,passed:false,code:error.code??'voice_check_failed'}));process.exitCode=1;}
