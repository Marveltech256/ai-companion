import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createTextAi,createMemoryReranker,BackupTextAi} from '../../supabase/functions/_shared/text_ai.ts';
import type {TextAi} from '../../supabase/functions/_shared/text_ai.ts';
import {GeminiProvider} from '../../supabase/functions/_shared/gemini.ts';
import {ProviderError} from '../../supabase/functions/_shared/provider_error.ts';
import {createConversationTurn} from '../../supabase/functions/_shared/conversation_turn.ts';
import type {ReplyInput} from '../../supabase/functions/_shared/openai.ts';
import {groundedCandidates} from '../../supabase/functions/_shared/memory.ts';
import type {ContextMemory} from '../../supabase/functions/_shared/companion_context.ts';

const input:ReplyInput={companion:{id:randomUUID(),name:'Lumi',communication_style:'Gentle & warm',memory_enabled:false,response_length:.5},
 history:[{role:'user',content:'Hello'}],memories:[{category:'preferences',content:'PRIVATE OPTED-OUT FACT'}]};
const settings:Record<string,string>={OPENAI_API_KEY:'openai-test-secret',OPENAI_MODEL:'openai-test-model',GEMINI_API_KEY:'gemini-test-secret',GEMINI_MODEL:'gemini-test-model'};
const config=(name:string)=>settings[name];
const signal=()=>new AbortController().signal;
const sse=(...events:unknown[])=>new Response(events.map(event=>`data: ${JSON.stringify(event)}\n\n`).join(''));
const geminiDone=(text:string)=>({candidates:[{content:{parts:[{text}]},finishReason:'STOP'}]});
async function collect(provider:TextAi|GeminiProvider,data=input,abort=signal()){
 let output='';for await(const delta of provider.reply(data,abort))output+=delta;return output;
}

test('OpenAI remains primary; Gemini gets the same bounded consent context only on transient failure',async()=>{
 const calls:{url:string;headers:Headers;body:any}[]=[];
 const ai=createTextAi(config,async(url,init)=>{
  calls.push({url:String(url),headers:new Headers(init?.headers),body:JSON.parse(init?.body as string)});
  if(String(url).includes('api.openai.com'))return new Response('{}',{status:503});
  return sse({candidates:[{content:{parts:[{text:'private reasoning',thought:true},{text:'Hello, '}]}}]},geminiDone('Marvin.'));
 });
 assert.equal(await collect(ai),'Hello, Marvin.');assert.equal(calls.length,2);
 assert.equal(calls[0].headers.get('Authorization'),'Bearer openai-test-secret');
 assert.equal(calls[1].headers.get('x-goog-api-key'),'gemini-test-secret');
 assert.equal(calls[1].headers.get('Authorization'),null);
 assert.ok(calls[1].url.endsWith(':streamGenerateContent?alt=sse'));
 assert.ok(!calls.some(c=>c.url.includes('secret')));
 assert.ok(!JSON.stringify(calls[1].body).includes('PRIVATE OPTED-OUT FACT'));
 assert.equal(calls[1].body.contents[0].parts[0].text,'Hello');
 assert.equal(calls[1].body.generationConfig.maxOutputTokens,1800);
 let backups=0;
 const primary=createTextAi(config,async url=>{
  if(!String(url).includes('api.openai.com'))backups++;
  return sse({type:'response.output_text.delta',delta:'Primary reply'},{type:'response.completed'});
 });
 assert.equal(await collect(primary),'Primary reply');assert.equal(backups,0);
});

test('partial output, refusal and invalid/auth requests never switch providers',async()=>{
 let backups=0;
 const ai=createTextAi(config,async url=>{
  if(!String(url).includes('api.openai.com'))backups++;
  return sse({type:'response.output_text.delta',delta:'Visible primary text'},{type:'response.failed'});
 });
 let visible='';await assert.rejects(async()=>{for await(const delta of ai.reply(input,signal()))visible+=delta;});
 assert.equal(visible,'Visible primary text');assert.equal(backups,0);
 for(const status of [400,401,403]){
  let calls=0;await assert.rejects(collect(createTextAi(config,async()=>{calls++;return new Response('{}',{status});})));
  assert.equal(calls,1);
 }
 const refusal=createTextAi(config,async()=>sse({type:'response.refusal.delta',delta:'I cannot help with that.'},{type:'response.completed'}));
 assert.equal(await collect(refusal),'I cannot help with that.');
});

test('cancellation prevents failover; a primary first-token timeout can use the backup',async()=>{
 let backupCalls=0;
 const backup:TextAi={async *reply(){backupCalls++;yield 'Backup';},async extract(){backupCalls++;return {memories:[]};},async rank(){return [];}};
 const primary:TextAi={async *reply(_input,abort){await new Promise((_,reject)=>abort.addEventListener('abort',()=>reject(abort.reason),{once:true}));},
  async extract(){throw new ProviderError(503,'ai_unavailable','Unavailable',true);},async rank(){return [];}};
 const ai=new BackupTextAi(primary,backup,5);
 assert.equal(await collect(ai),'Backup');assert.equal(backupCalls,1);
 const cancelled=AbortSignal.abort();
 await assert.rejects(collect(ai,input,cancelled));assert.equal(backupCalls,1);
 const during=new AbortController();const pending=collect(new BackupTextAi(primary,backup,10000),input,during.signal);
 during.abort();await assert.rejects(pending);assert.equal(backupCalls,1);
});

test('memory fallback preserves the exact schema, provenance, grounding and owned ranking IDs',async()=>{
 const requests:any[]=[];
 const source='I like gardening.';
 const ai=createTextAi(config,async(url,init)=>{
  if(String(url).includes('api.openai.com'))return new Response('{}',{status:429});
  const body=JSON.parse(init?.body as string);requests.push(body);
  const object=body.generationConfig.maxOutputTokens===650?{ids:['foreign','owned','owned']}:
   {memories:[{key:'preferences.gardening',category:'preferences',quote:source,confidence:.99,importance:.5},
    {key:'preferences.invented',category:'preferences',quote:'I like skiing.',confidence:.99,importance:.5}]};
  return Response.json(geminiDone(JSON.stringify(object)));
 });
 const extracted=await ai.extract(source,signal(),{created_at:'2026-11-03T09:00:00Z',timezone:'Africa/Kampala',previous_assistant:'What do you enjoy?'});
 assert.equal(groundedCandidates(extracted,source).length,1);
 assert.equal(requests[0].generationConfig.responseMimeType,'application/json');
 assert.equal(requests[0].generationConfig.responseJsonSchema.properties.memories.maxItems,5);
 assert.equal(JSON.parse(requests[0].contents[0].parts[0].text).source_timezone,'Africa/Kampala');
 const owned={id:'owned',kind:'preference',content:'Gardening',verification:'confirmed'} as ContextMemory;
 assert.deepEqual(await ai.rank('gardening',[owned],signal()),['owned']);
 assert.equal(createMemoryReranker(config),undefined);
});

test('Gemini rejects blocked, truncated, empty or unterminated responses without leaking thought text',async()=>{
 for(const event of [{promptFeedback:{blockReason:'SAFETY'}},
  {candidates:[{content:{parts:[{text:'truncated'}]},finishReason:'MAX_TOKENS'}]},
  {candidates:[{content:{parts:[{text:'thought',thought:true}]},finishReason:'STOP'}]},
  {candidates:[{content:{parts:[{text:'partial'}]}}]}]){
  const ai=new GeminiProvider('secret','model','model',async()=>sse(event));await assert.rejects(collect(ai));
 }
});

test('fallback configuration is optional and never invents an answer if both providers fail',async()=>{
 for(const override of [{GEMINI_BACKUP_ENABLED:'false'},{GEMINI_API_KEY:''},{GEMINI_MODEL:''}]){
  let calls=0;const values={...settings,...override};
  await assert.rejects(collect(createTextAi(name=>values[name],async()=>{calls++;return new Response('{}',{status:503});})));
  assert.equal(calls,1);
 }
 let calls=0;await assert.rejects(collect(createTextAi(config,async()=>{calls++;return new Response('{}',{status:503});})));
 assert.equal(calls,2);
});

test('a failed primary followed by Gemini persists exactly one assistant response for the same turn',async()=>{
 const stored:any[]=[];let failures=0;
 const ai=createTextAi(config,async url=>String(url).includes('api.openai.com')?new Response('{}',{status:503}):sse(geminiDone('A single backup reply.')));
 const handler=createConversationTurn({origins:[],verify:async()=>({uid:'alice'}),ai,db:{rpc:async<T>(name,args)=>{
  if(name==='morrow_access_begin_turn')return {status:'running',lease:randomUUID(),companion:input.companion,history:input.history} as T;
  if(name==='morrow_complete_turn')stored.push(args);
  if(name==='morrow_fail_turn')failures++;
  return {ok:true} as T;
 }}});
 const response=await handler(new Request('https://local.test',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({conversation_id:randomUUID(),request_id:randomUUID(),content:'Hello'})}));
 const stream=await response.text();assert.match(stream,/"done"/);
 assert.equal(stored.length,1);assert.equal(stored[0].p_content,'A single backup reply.');assert.equal(failures,0);
});
