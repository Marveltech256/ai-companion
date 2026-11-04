import {ApiError} from './errors.ts';
import {boundedBody} from './http.ts';
import {boundedHistory,companionInstructions,memoryExtractionRequest,memoryRankingRequest,serverEvents} from './openai.ts';
import type {AiProvider,ReplyInput,HistoryMessage} from './openai.ts';
import type {MemorySourceContext} from './memory.ts';
import type {ContextMemory} from './companion_context.ts';
import {ProviderError,providerUnavailable,transientProviderStatus} from './provider_error.ts';

interface Candidate {content?:{parts?:{text?:string;thought?:boolean}[]};finishReason?:string}
interface GeminiResult {candidates?:Candidate[];promptFeedback?:{blockReason?:string};error?:unknown}

function candidate(result:GeminiResult):Candidate|undefined {
 if(result.promptFeedback?.blockReason&&result.promptFeedback.blockReason!=='BLOCK_REASON_UNSPECIFIED')
  throw new ProviderError(503,'ai_response_blocked','Your companion could not complete that reply.',false);
 if(result.error)throw providerUnavailable();
 const value=result.candidates?.[0];
 if(value?.finishReason&&value.finishReason!=='STOP'&&value.finishReason!=='FINISH_REASON_UNSPECIFIED')
  throw new ProviderError(503,'generation_failed','Reply interrupted. Please try again.',false);
 return value;
}
const text=(value:Candidate|undefined)=>(value?.content?.parts??[]).filter(p=>!p.thought&&typeof p.text==='string').map(p=>p.text).join('');

function contents(history:HistoryMessage[]) {
 const items:{role:string;parts:{text:string}[]}[]=[];
 for(const item of boundedHistory(history)){
  const role=item.role==='assistant'?'model':'user';
  if(items.at(-1)?.role===role)items.at(-1)!.parts.push({text:item.content});
  else items.push({role,parts:[{text:item.content}]});
 }
 if(!items.length||items.at(-1)?.role==='model')items.push({role:'user',parts:[{
  text:'Application control message: follow the supplied operation instructions to produce the assistant opening. This is not a user-authored conversation message.',
 }]});
 return items;
}

export class GeminiProvider implements AiProvider {
 constructor(private key:string,private model:string,private memoryModel:string=model,private fetcher=fetch){}
 private async request(model:string,body:Record<string,unknown>,stream:boolean,signal:AbortSignal){
  signal.throwIfAborted();
  if(!this.key||!model)throw new ProviderError(503,'ai_not_configured','Conversations are not connected yet.',true);
  if(!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,150}$/.test(model))throw new ProviderError(503,'ai_not_configured','Conversations are not connected yet.',false);
  let response:Response;
  try{response=await this.fetcher(`https://generativelanguage.googleapis.com/v1beta/models/${model}:${stream?'streamGenerateContent?alt=sse':'generateContent'}`,{
   method:'POST',headers:{'x-goog-api-key':this.key,'Content-Type':'application/json'},body:JSON.stringify(body),signal,
  });}catch(error){if(signal.aborted)throw error;throw providerUnavailable();}
  if(!response.ok){await response.body?.cancel();throw new ProviderError(response.status===429?429:503,'ai_unavailable',
   "Your companion couldn't reply just now. Please try again.",transientProviderStatus(response.status));}
  return response;
 }
 async *reply(input:ReplyInput,signal:AbortSignal):AsyncGenerator<string>{
  const response=await this.request(this.model,{
   systemInstruction:{parts:[{text:companionInstructions(input.companion,input.memories,input.observations,input.context,input.purpose,input.reason)}]},
   contents:contents(input.history),generationConfig:{candidateCount:1,maxOutputTokens:1800},
  },true,signal);
  if(!response.body)throw providerUnavailable();
  let finished=false,emitted=false;
  try{for await(const event of serverEvents(response.body)){
   signal.throwIfAborted();const value=candidate(event as GeminiResult);const delta=text(value);
   if(delta){emitted=true;yield delta;}
   if(value?.finishReason==='STOP')finished=true;
  }}catch(error){if(error instanceof ApiError||signal.aborted)throw error;throw providerUnavailable();}
  if(!finished||!emitted)throw providerUnavailable();
 }
 private async json(request:ReturnType<typeof memoryExtractionRequest>|ReturnType<typeof memoryRankingRequest>,signal:AbortSignal):Promise<unknown>{
  const response=await this.request(request.model,{
   systemInstruction:{parts:[{text:request.instructions}]},
   contents:request.input.map(item=>({role:'user',parts:[{text:item.content}]})),
   generationConfig:{candidateCount:1,maxOutputTokens:request.max_output_tokens,
    responseMimeType:'application/json',responseJsonSchema:request.text.format.schema},
  },false,signal);
  try{
   const result=JSON.parse(new TextDecoder().decode(await boundedBody(response,1048576))) as GeminiResult;
   const value=candidate(result);
   if(value?.finishReason!=='STOP')throw providerUnavailable();
   return JSON.parse(text(value));
  }catch(error){if(error instanceof ApiError||signal.aborted)throw error;throw providerUnavailable();}
 }
 extract(content:string,signal:AbortSignal,source?:MemorySourceContext):Promise<unknown>{
  return this.json(memoryExtractionRequest(content,this.memoryModel,source),signal);
 }
 async rank(query:string,candidates:ContextMemory[],signal:AbortSignal):Promise<string[]>{
  const result=await this.json(memoryRankingRequest(query,candidates,this.model),signal) as {ids?:unknown};
  if(!Array.isArray(result.ids))return [];
  const owned=new Set(candidates.map(c=>c.id));
  return [...new Set(result.ids.filter((id:unknown):id is string=>typeof id==='string'&&owned.has(id)))];
 }
}
