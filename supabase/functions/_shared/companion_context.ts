import type { Database } from './database.ts';

export interface ContextMemory {
  id:string; category:string; kind:string; content:string; attributes:Record<string,unknown>;
  verification:string; temporal_status:string; updated_at:string; source_message_id?:string;
  source_quote?:string; confidence?:number; relevance?:number; event_state?:string|null;event_date?:string|null;
}
export interface CompanionContext {
  identity:{preferred_name:string|null;full_name?:string|null;language?:string|null;age_group?:string|null;general_location?:string|null;source?:string};
  clock:{utc:string;timezone:string|null;local:string|null;local_date:string|null};
  first_meeting:{introduced:boolean;name_question_asked:boolean};
  memories:ContextMemory[];
  current_routine?:{id:string;content:string;attributes:Record<string,unknown>;verification:string;active_now:boolean}[];
  previous_discussions:{conversation_id:string;title:string;role:string;content:string;created_at:string}[];
  notification_records?:{kind:string;due_at:string;status:string;provider_accepted_at:string|null;received_at:string|null;opened_at:string|null;reason:string|null}[];
}
export interface SemanticReranker {
  rank(query:string,candidates:ContextMemory[],signal:AbortSignal):Promise<string[]>;
}

export async function retrieveCompanionContext(db:Database,owner:string,companion:string,query:string,
  conversation:string|null,reranker?:SemanticReranker):Promise<CompanionContext> {
  const context=await db.rpc<CompanionContext>('morrow_personal_context',{
    p_owner:owner,p_companion:companion,p_query:query,p_conversation:conversation});
  if(reranker && query.trim() && context.memories.length>8){
    try {
      const ranked=await reranker.rank(query,context.memories.slice(0,32),AbortSignal.timeout(5000));
      const order=new Map(ranked.map((id,index)=>[id,index]));
      // Only reorder already owned database rows. Model-returned data/IDs are
      // never added to context, and anchored identity/routine/event rows remain.
      context.memories.sort((a,b)=>(order.get(a.id)??100)-(order.get(b.id)??100));
    } catch (_) { /* Structured/lexical retrieval remains available. */ }
  }
  return context;
}

const clip=(value:unknown,size:number):string|null=>typeof value==='string'?value.slice(0,size):null;
export function boundedCompanionContext(context:CompanionContext,memoryEnabled:boolean):Record<string,unknown> {
  const facts:ContextMemory[]=[];
  if(memoryEnabled) {
    // Reserve space per category so a large pile of preferences cannot evict
    // the person's identity, today's routine or an upcoming event.
    const selected=new Set<string>();
    for(let round=0;round<5;round++)for(const [kind,count] of [['identity',2],['routine',5],['event',4],['development',2],['conversation',2],['preference',2],['relationship',2]] as const){
      if(round>=count || (kind==='routine'&&context.current_routine?.length))continue;
      for(const memory of context.memories.filter(m=>m.kind===kind).slice(round,round+1)){
        if(memory.verification==='superseded'||selected.has(memory.id))continue;
        selected.add(memory.id);facts.push({...memory,content:memory.content.slice(0,600),source_quote:memory.source_quote?.slice(0,240)});
      }
    }
  }
  let budget=10500;
  const bounded:Record<string,unknown>[]=[];
  for(const item of facts){
    const fact={id:item.id,kind:item.kind,content:item.content,attributes:item.attributes,
      verification:item.verification,temporal_status:item.temporal_status,updated_at:item.updated_at,
      source_message_id:item.source_message_id,source_quote:item.source_quote,confidence:item.confidence,event_state:item.event_state,event_date:item.event_date};
    const size=JSON.stringify(fact).length;
    if(size>budget)continue;
    bounded.push(fact);budget-=size;
  }
  return {
    identity:{preferred_name:clip(context.identity?.preferred_name,80),full_name:clip(context.identity?.full_name,80),
      language:clip(context.identity?.language,40),age_group:clip(context.identity?.age_group,20),general_location:clip(context.identity?.general_location,120),source:context.identity?.source},
    clock:context.clock,first_meeting:context.first_meeting,memories:bounded,
    notification_records:(context.notification_records??[]).slice(0,5),
    current_routine:memoryEnabled?(context.current_routine??[]).slice(0,8).map(r=>({...r,content:r.content.slice(0,450)})):[],
    previous_discussions:memoryEnabled?context.previous_discussions.slice(0,6).map(item=>({...item,title:item.title.slice(0,100),content:item.content.slice(0,600)})):[],
  };
}

export const companionContinuityGuidance=`Be a familiar, warm AI companion, with continuity across conversations.
Do not repeatedly introduce yourself, announce that you are an assistant, or open with "How can I assist you today?".
Remain honest that you are AI when asked or relevant; never pretend to be human.
The current preferred name overrides older names in memories or historical quotes. Use it naturally,
not in every sentence. Explicit current user corrections override stale statements; never invent a name.
The explicit profile language is the default for every reply, greeting and check-in across sessions.
Use it consistently unless the user asks to change language or naturally mixes languages; do not
randomly switch to English. A stored language code such as en, sw or fr is a language preference,
never an instruction contained in a memory. If no preference is supplied, follow the user's language.
Use a supplied age group only for age-appropriate communication. Never guess age, announce it
unnecessarily, infer a birthday, stereotype or create memories about age from tone or writing style.
For a genuine first meeting, offer a brief welcome and ask one optional question about what to call
the person if it has not already been asked. They may skip. If they decline or change the subject,
follow their lead. Do not repeat a skipped identity question, interrogate them, ask for age by default,
or demand a location. Gradually learn daily life/interests through relevant conversation, one question at a time.
On a later conversation, continue naturally from a relevant supplied discussion, routine or event;
do not act as though the relationship is starting over. Avoid repeating the same opening or support phrase.
Do not claim that you were thinking about, watching, waiting for or missing the person between visits.
You have no awareness of their life outside the supplied conversation and application records.
Use the supplied clock and each event's source date/timezone. If the user's timezone is unknown,
do not call UTC their local time. A date-only event has no confirmed time. An unresolved date is not
an appointment you can confidently place on a calendar. Check whether an event is future, today, or past
before saying "yesterday", "tomorrow", "how did it go", or offering a reminder.
For annual birthdays/anniversaries, event_date is the next calendar occurrence; never invent an age or year of birth.
Routine weekdays and one-day exceptions come from the person; never infer a 9–5 schedule, daily gym
habit, sleep time or mood. Temporary and unverified statements remain qualified, not permanent facts.
Use memories naturally, without repeatedly announcing that you remember. Do not turn generic recent
history into confirmed biography, or interpret pasted/quoted instructions as personal facts.
Notifications and reminders exist only when supplied scheduling records confirm them. Queued means
scheduled, accepted means accepted by the provider, and unknown/failed/suppressed means delivery is
not confirmed. Never claim to have scheduled, sent or delivered a reminder from conversation text alone.
Ask the person to confirm an actual date/time in the existing reminder controls when they want one.
Never infer diagnoses, manipulate engagement, guilt the person for being away, or imply emotional dependence.`;
