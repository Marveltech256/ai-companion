import {OpenAIAudio} from './voice.ts';
import type {AudioProvider} from './voice.ts';
import {GeminiAudio} from './gemini_audio.ts';

export function audioCapabilities(get:(name:string)=>string|undefined){
 const gemini=get('GEMINI_BACKUP_ENABLED')!=='false'&&!!get('GEMINI_API_KEY');
 return {welcome_audio:!!get('OPENAI_API_KEY')&&!!get('OPENAI_SPEECH_MODEL')||gemini&&!!get('GEMINI_SPEECH_MODEL'),
  transcription:!!get('OPENAI_API_KEY')&&!!get('OPENAI_TRANSCRIPTION_MODEL')||gemini&&!!get('GEMINI_TRANSCRIPTION_MODEL')};
}
export function createAudioProvider(get:(name:string)=>string|undefined,fetcher=fetch):AudioProvider{
 const openai=new OpenAIAudio(get('OPENAI_API_KEY')??'',get('OPENAI_TRANSCRIPTION_MODEL')??'',get('OPENAI_SPEECH_MODEL')??'',get('OPENAI_SPEECH_VOICE')??'marin',fetcher);
 const gemini=new GeminiAudio(get('GEMINI_BACKUP_ENABLED')==='false'?'':get('GEMINI_API_KEY')??'',get('GEMINI_TRANSCRIPTION_MODEL')??'',get('GEMINI_SPEECH_MODEL')??'',get('GEMINI_SPEECH_VOICE')??'Kore',fetcher);
 const speech=get('OPENAI_API_KEY')&&get('OPENAI_SPEECH_MODEL')?openai:gemini;
 const transcription=get('OPENAI_API_KEY')&&get('OPENAI_TRANSCRIPTION_MODEL')?openai:gemini;
 return {speechMimeType:speech.speechMimeType,transcribe:(wav,signal)=>transcription.transcribe(wav,signal),speech:(text,signal)=>speech.speech(text,signal)};
}
