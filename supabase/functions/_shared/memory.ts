import type { Database } from './database.ts';
import { memoryCategories } from './openai.ts';

export interface MemorySourceContext {id?:string;created_at?:string;timezone?:string|null;previous_assistant?:string|null}
export interface MemoryCandidate {key:string;category:string;quote:string;confidence:number;importance:number;attributes?:Record<string,unknown>}
export interface MemoryExtractor {extract(content:string,signal:AbortSignal,source?:MemorySourceContext):Promise<unknown>}

export function groundedCandidates(value:unknown,source:string):MemoryCandidate[]{
  const rows=(value as {memories?:unknown[]})?.memories;
  if(!Array.isArray(rows))return [];
  const keys=new Set<string>(),result:MemoryCandidate[]=[];
  for(const row of rows.slice(0,5)){
    if(!row || typeof row!=='object')continue;
    const item=row as MemoryCandidate;
    if(typeof item.key!=='string' || !/^[a-z0-9_.:-]{1,120}$/.test(item.key) || keys.has(item.key) ||
      !memoryCategories.includes(item.category) || typeof item.quote!=='string' ||
      item.quote.trim().length<(item.attributes?.field==='preferred_name'?1:4) || item.quote.length>2000 || !source.includes(item.quote.trim()) ||
      !Number.isFinite(item.confidence) || item.confidence<.8 || item.confidence>1 ||
      !Number.isFinite(item.importance) || item.importance<0 || item.importance>1 ||
      /\b(password|passcode|api[- ]?key|secret token|social security|credit card|passport number)\b/i.test(item.quote) ||
      /(?:\d[ -]?){13,19}/.test(item.quote))continue;
    if(item.attributes!==undefined){
      if(!item.attributes || typeof item.attributes!=='object'||Array.isArray(item.attributes)||JSON.stringify(item.attributes).length>4000)continue;
      if(item.attributes.value!==null && item.attributes.value!==undefined &&
        (typeof item.attributes.value!=='string'||!item.quote.toLocaleLowerCase().includes(item.attributes.value.toLocaleLowerCase())))continue;
      if(item.attributes.field==='preferred_name')item.key='identity.preferred_name';
    }
    if(keys.has(item.key))continue;
    keys.add(item.key);result.push({...item,quote:item.quote.trim()});
  }
  return result;
}

export async function processMemoryJob(db:Database,ai:MemoryExtractor,owner:string,requestId:string):Promise<void>{
  const claimed=await db.rpc<{job:null|{lease:string};source:MemorySourceContext&{content:string}}>(
    'morrow_claim_memory_job',{p_owner:owner,p_request:requestId});
  if(!claimed.job)return;
  const lease=claimed.job.lease;
  try{
    const result=await ai.extract(claimed.source.content,AbortSignal.timeout(30000),claimed.source);
    const candidates=groundedCandidates(result,claimed.source.content);
    await db.rpc(candidates.some(c=>c.attributes!==undefined)?'morrow_apply_companion_memory_job':'morrow_apply_memory_job',{
      p_owner:owner,p_request:requestId,p_lease:lease,p_candidates:candidates});
  }catch(error){
    await db.rpc('morrow_fail_memory_job',{p_owner:owner,p_request:requestId,p_lease:lease}).catch(()=>{});
    throw error;
  }
}
