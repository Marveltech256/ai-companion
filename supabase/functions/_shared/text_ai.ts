import {OpenAIResponses} from './openai.ts';
import type {AiProvider,ReplyInput} from './openai.ts';
import type {MemoryExtractor,MemorySourceContext} from './memory.ts';
import type {SemanticReranker,ContextMemory} from './companion_context.ts';
import {GeminiProvider} from './gemini.ts';
import {ProviderError} from './provider_error.ts';

export interface TextAi extends AiProvider,MemoryExtractor,SemanticReranker {}

function attemptSignal(parent:AbortSignal,timeout:number){
 const controller=new AbortController();let timedOut=false;
 const timer=setTimeout(()=>{timedOut=true;controller.abort(new DOMException('Provider timed out','TimeoutError'));},timeout);
 return {signal:AbortSignal.any([parent,controller.signal]),timedOut:()=>timedOut,
  firstOutput:()=>clearTimeout(timer),close:()=>{clearTimeout(timer);controller.abort();}};
}

/** A visible partial response is never replaced with a second provider's text. */
export class BackupTextAi implements TextAi {
 constructor(private primary:TextAi,private backup:TextAi,private firstOutputMs=15000,private structuredMs=12000){}
 async *reply(input:ReplyInput,signal:AbortSignal):AsyncGenerator<string>{
  signal.throwIfAborted();let emitted=false;
  const attempt=attemptSignal(signal,this.firstOutputMs);
  try{
   for await(const delta of this.primary.reply(input,attempt.signal)){
    signal.throwIfAborted();if(!delta)continue;
    emitted=true;attempt.firstOutput();yield delta;
   }
   return;
  }catch(error){
   if(signal.aborted||emitted||(!attempt.timedOut()&&!(error instanceof ProviderError&&error.allowFallback)))throw error;
  }finally{attempt.close();}
  signal.throwIfAborted();console.warn('ai_backup_used:reply');
  for await(const delta of this.backup.reply(input,signal)){signal.throwIfAborted();yield delta;}
 }
 private async structured<T>(operation:'extract'|'rank',signal:AbortSignal,work:(provider:TextAi,signal:AbortSignal)=>Promise<T>):Promise<T>{
  signal.throwIfAborted();const attempt=attemptSignal(signal,operation==='rank'?2000:this.structuredMs);
  try{return await work(this.primary,attempt.signal);}
  catch(error){if(signal.aborted||(!attempt.timedOut()&&!(error instanceof ProviderError&&error.allowFallback)))throw error;}
  finally{attempt.close();}
  signal.throwIfAborted();console.warn(`ai_backup_used:${operation}`);return work(this.backup,signal);
 }
 extract(content:string,signal:AbortSignal,source?:MemorySourceContext):Promise<unknown>{
  return this.structured('extract',signal,(provider,attempt)=>provider.extract(content,attempt,source));
 }
 rank(query:string,candidates:ContextMemory[],signal:AbortSignal):Promise<string[]>{
  return this.structured('rank',signal,(provider,attempt)=>provider.rank(query,candidates,attempt));
 }
}

export function createTextAi(get:(name:string)=>string|undefined,fetcher=fetch):TextAi {
 const model=get('OPENAI_MODEL')??'';
 const primary=new OpenAIResponses(get('OPENAI_API_KEY')??'',model,get('OPENAI_MEMORY_MODEL')||model,fetcher);
 const geminiModel=get('GEMINI_MODEL')??'',geminiKey=get('GEMINI_API_KEY')??'';
 if(get('GEMINI_BACKUP_ENABLED')==='false'||!geminiKey||!geminiModel)return primary;
 return new BackupTextAi(primary,new GeminiProvider(geminiKey,geminiModel,get('GEMINI_MEMORY_MODEL')||geminiModel,fetcher));
}
export function createMemoryReranker(get:(name:string)=>string|undefined,fetcher=fetch):SemanticReranker|undefined {
 if(!get('OPENAI_RETRIEVAL_MODEL')&&!get('GEMINI_RETRIEVAL_MODEL'))return undefined;
 return createTextAi(name=>name==='OPENAI_MODEL'?get('OPENAI_RETRIEVAL_MODEL'):
  name==='GEMINI_MODEL'?(get('GEMINI_RETRIEVAL_MODEL')||get('GEMINI_MODEL')):get(name),fetcher);
}
