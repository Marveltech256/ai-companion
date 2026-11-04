import type { Identity } from "./auth.ts";
import type { Database } from "./database.ts";
import { ApiError, requiredString, uuid } from "./errors.ts";
import { cors, errorResponse, jsonBody } from "./http.ts";
import { memoryCategories } from './openai.ts';
import {friendPreferencesInput} from './friend_preferences.ts';

export interface ApiDependencies {
  db: Database;
  verify(request: Request): Promise<Identity>;
  origins: string[];
  recover?(owner:string):Promise<void>;
  defer?(work:Promise<void>):void;
  eligible?(owner:string):Promise<void>;
  friendEligible?(owner:string):Promise<void>;
  capabilities?:{welcome_audio:boolean;transcription?:boolean;billing?:boolean};
}

function booleanInput(value:unknown):boolean {
  if(typeof value!=='boolean')throw new ApiError(400,'invalid_input','Please check your preferences.');
  return value;
}
function minuteInput(value:unknown):number {
  if(!Number.isInteger(value) || (value as number)<0 || (value as number)>1439)
    throw new ApiError(400,'invalid_input','Choose a valid time.');
  return value as number;
}
function optionalText(value:unknown,label:string,max:number):string|null {
  return value==null || value===''?null:requiredString(value,label,max);
}

export function companionInput(body: Record<string, unknown>) {
  const name = requiredString(body.name, "name", 24);
  const style = requiredString(body.style, "style", 32);
  const styles = ["Gentle & warm", "Playful", "Reflective"];
  const allowed = ["Art & making", "Music", "Little adventures", "Books", "Cooking"];
  if (!styles.includes(style) || !Array.isArray(body.interests) ||
      body.interests.length > 5 || body.interests.some(x => !allowed.includes(x as string)) ||
      typeof body.memory_enabled !== "boolean" || typeof body.response_length !== "number" ||
      !Number.isFinite(body.response_length) || body.response_length < 0 || body.response_length > 1 ||
      (body.retention_days !== null && (!Number.isInteger(body.retention_days) ||
        (body.retention_days as number) < 1 || (body.retention_days as number) > 3650))) {
    throw new ApiError(400, "invalid_input", "Please check your companion settings.");
  }
  return { p_name: name, p_style: style, p_interests: [...new Set(body.interests)],
    p_response_length: body.response_length, p_memory_enabled: body.memory_enabled,
    p_retention_days: body.retention_days };
}

export function createCompanionApi(deps: ApiDependencies) {
  return async (request: Request): Promise<Response> => {
    let headers = new Headers({ "Cache-Control": "no-store" });
    try {
      headers = cors(request, deps.origins);
      if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
      if (request.method !== "POST") throw new ApiError(405,"method_not_allowed","POST is required.");
      const identity = await deps.verify(request);
      const body = await jsonBody(request);
      if(!['bootstrap','save_profile','save_personal_profile','save_introduction','complete_welcome','notification_preferences'].includes(body.action as string))
        await deps.eligible?.(identity.uid);
      const args: Record<string, unknown> = { p_owner: identity.uid };
      let rpc: string;
      switch (body.action) {
        case 'save_friend_preferences':
          rpc='morrow_save_friend_preferences';args.p_companion=uuid(body.companion_id);
          Object.assign(args,friendPreferencesInput(body));break;
        case 'report_message':
          rpc='morrow_report_message';args.p_request=uuid(body.request_id);args.p_message=uuid(body.message_id);
          args.p_reason=requiredString(body.reason,'report reason',20);
          args.p_details=body.details==null?'':typeof body.details==='string'&&body.details.length<=2000?body.details:requiredString(null,'report details');break;
        case "bootstrap": rpc = "morrow_bootstrap"; break;
        case 'save_introduction':
          rpc='morrow_save_introduction';
          args.p_age_group=optionalText(body.age_group,'age group',20);
          args.p_language=requiredString(body.language,'language',40);
          args.p_timezone=requiredString(body.timezone,'timezone',80);
          if(body.timezone_automatic!==undefined){rpc='morrow_save_friend_introduction';args.p_automatic=booleanInput(body.timezone_automatic);}break;
        case 'save_timezone':
          rpc='morrow_save_timezone';args.p_timezone=requiredString(body.timezone,'timezone',80);args.p_automatic=booleanInput(body.automatic);break;
        case 'set_reply_mode':rpc='morrow_reply_mode';args.p_mode=requiredString(body.mode,'reply mode',10);break;
        case 'activate_friend_mode':
          rpc='morrow_activate_friend_mode';args.p_companion=uuid(body.companion_id);args.p_consent=booleanInput(body.consent);break;
        case 'complete_welcome':rpc='morrow_complete_welcome';break;
        case 'home_summary':rpc='morrow_home_summary';args.p_companion=uuid(body.companion_id);break;
        case "save_profile":
          rpc = "morrow_save_profile";
          args.p_display_name = requiredString(body.display_name,"display name",80);
          break;
        case 'save_personal_profile':
          rpc='morrow_save_personal_profile';
          if(body.username!==undefined){rpc='morrow_save_named_profile';args.p_username=optionalText(body.username,'username',30);}
          args.p_preferred_name=optionalText(body.preferred_name,'preferred name',80);
          args.p_display_name=optionalText(body.display_name,'name',80);
          args.p_timezone=optionalText(body.timezone,'timezone',80);
          args.p_language=optionalText(body.language,'language',40);
          args.p_location=optionalText(body.general_location,'general location',120);break;
        case "save_companion":
          rpc = "morrow_save_companion";
          Object.assign(args, companionInput(body));
          break;
        case 'list_conversations': rpc='morrow_list_conversations'; break;
        case 'set_learning':
          rpc='morrow_set_learning';args.p_companion=uuid(body.companion_id);
          if(typeof body.enabled!=='boolean')throw new ApiError(400,'invalid_input','Choose whether learning is enabled.');
          args.p_enabled=body.enabled;break;
        case 'set_voice':
          rpc='morrow_set_voice';args.p_companion=uuid(body.companion_id);
          args.p_enabled=booleanInput(body.enabled);break;
        case 'personalization':
          rpc='morrow_personalization';args.p_companion=uuid(body.companion_id);break;
        case 'notification_preferences': rpc='morrow_notification_preferences';break;
        case 'save_notification_preferences':
          rpc='morrow_save_notification_preferences';args.p_companion=uuid(body.companion_id);
          args.p_checkins=booleanInput(body.checkins_enabled);
          args.p_suggestions=booleanInput(body.suggestions_enabled);
          args.p_birthdays=booleanInput(body.birthdays_enabled);
          args.p_timezone=body.timezone==null?null:requiredString(body.timezone,'timezone',80);
          args.p_local_minute=minuteInput(body.local_minute);
          args.p_quiet_start=minuteInput(body.quiet_start);args.p_quiet_end=minuteInput(body.quiet_end);
          if(!Array.isArray(body.weekdays)||body.weekdays.length<1||body.weekdays.length>7||
            body.weekdays.some(x=>!Number.isInteger(x)||x<0||x>6))
            throw new ApiError(400,'invalid_input','Choose valid days.');
          args.p_weekdays=[...new Set(body.weekdays)];
          if(body.additional_minutes!==undefined || body.max_per_day!==undefined){
            if(!Array.isArray(body.additional_minutes)||body.additional_minutes.length>2||
              !Number.isInteger(body.max_per_day)||(body.max_per_day as number)<1||(body.max_per_day as number)>3)
              throw new ApiError(400,'invalid_input','Choose up to three check-ins per day.');
            rpc='morrow_save_personal_schedule';args.p_additional=body.additional_minutes.map(minuteInput);args.p_max=body.max_per_day;
            if(body.inactivity_days!==undefined){
              if(!Number.isInteger(body.inactivity_days)||(body.inactivity_days as number)<0||(body.inactivity_days as number)>14)
                throw new ApiError(400,'invalid_input','Choose an inactivity period from 0 to 14 days.');
              rpc='morrow_save_friend_schedule';args.p_inactivity_days=body.inactivity_days;
            }
          }break;
        case 'checkin_history':rpc='morrow_checkin_history';break;
        case 'checkin_receipt':
          rpc='morrow_checkin_receipt';args.p_id=uuid(body.id);args.p_opened=booleanInput(body.opened);break;
        case 'schedule_personal_reminder':
          rpc='morrow_schedule_personal_reminder';args.p_kind=requiredString(body.kind,'kind',20);
          if(!['followup','important_date'].includes(args.p_kind as string)||typeof body.local_time!=='string'||
            !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:00)?$/.test(body.local_time))throw new ApiError(400,'invalid_input','Choose a valid local date and time.');
          args.p_local=body.local_time;args.p_zone=requiredString(body.timezone,'timezone',80);
          args.p_reason=requiredString(body.reason,'reminder',2000);
          args.p_conversation=body.conversation_id==null?null:uuid(body.conversation_id);
          args.p_source=body.source_memory_id==null?null:uuid(body.source_memory_id);
          args.p_request=uuid(body.request_id);break;
        case 'register_device':
          rpc='morrow_register_device';args.p_installation=uuid(body.installation_id);
          args.p_token=requiredString(body.token,'device token',4096);break;
        case 'unregister_device':
          rpc='morrow_unregister_device';args.p_installation=uuid(body.installation_id);break;
        case 'schedule_followup':
          rpc='morrow_schedule_followup';args.p_kind=requiredString(body.kind,'kind',20);
          if(!['followup','important_date'].includes(args.p_kind as string)||
            typeof body.due_at!=='string'||!Number.isFinite(Date.parse(body.due_at)))
            throw new ApiError(400,'invalid_input','Choose a valid reminder date.');
          args.p_due=body.due_at;break;
        case 'cancel_checkin':rpc='morrow_cancel_checkin';args.p_id=uuid(body.id);break;
        case 'create_conversation':
          rpc='morrow_create_conversation';args.p_companion=uuid(body.companion_id);
          args.p_id=body.conversation_id==null?null:uuid(body.conversation_id);
          args.p_title=body.title==null?null:requiredString(body.title,'title',100);break;
        case 'messages':
          rpc='morrow_messages';args.p_conversation=uuid(body.conversation_id);
          if(body.before!=null){
            if(!Number.isSafeInteger(body.before) || (body.before as number)<1)
              throw new ApiError(400,'invalid_input','Invalid message cursor.');
            args.p_before=body.before;
          }
          break;
        case 'rename_conversation':
          rpc='morrow_rename_conversation';args.p_conversation=uuid(body.conversation_id);
          args.p_title=requiredString(body.title,'title',100);break;
        case 'delete_conversation':
          rpc='morrow_delete_conversation';args.p_conversation=uuid(body.conversation_id);break;
        case 'list_memories':
          rpc='morrow_list_memories';args.p_companion=uuid(body.companion_id);break;
        case 'search_memories':
          rpc='morrow_search_memories';args.p_companion=uuid(body.companion_id);
          args.p_query=requiredString(body.query,'query',12000);break;
        case 'save_memory':
          rpc='morrow_save_memory';args.p_companion=uuid(body.companion_id);
          args.p_id=body.id==null?null:uuid(body.id);
          args.p_category=requiredString(body.category,'category',40);
          if(!memoryCategories.includes(args.p_category as string))
            throw new ApiError(400,'invalid_input','Invalid memory category.');
          args.p_title=requiredString(body.title,'title',100);
          args.p_content=requiredString(body.content,'memory',2000);
          if(body.attributes!=null){
            if(typeof body.attributes!=='object'||Array.isArray(body.attributes)||JSON.stringify(body.attributes).length>4000)
              throw new ApiError(400,'invalid_input','Check the memory details.');
            rpc='morrow_save_structured_memory';args.p_attributes=body.attributes;
          }
          args.p_expires_at=body.expires_at??null;
          if(args.p_expires_at!==null && (typeof args.p_expires_at!=='string' ||
            !/^\d{4}-\d{2}-\d{2}T/.test(args.p_expires_at) ||
            !Number.isFinite(Date.parse(args.p_expires_at))))
            throw new ApiError(400,'invalid_input','Invalid retention date.');
          break;
        case 'forget_memory':rpc='morrow_forget_memory';args.p_id=uuid(body.id);break;
        case 'forget_all_memories':
          rpc='morrow_forget_all_memories';args.p_companion=uuid(body.companion_id);break;
        default: throw new ApiError(400,"unknown_action","Unknown action.");
      }
      const result=await deps.db.rpc(rpc,args);
      if(deps.recover && (body.action==='bootstrap' || body.action==='list_memories')){
        const work=deps.recover(identity.uid).catch(()=>console.error('memory_recovery_failed'));
        if(deps.defer)deps.defer(work);else await work;
      }
      return Response.json(body.action==='bootstrap'?{...result,capabilities:deps.capabilities??{welcome_audio:false}}:result, { headers });
    } catch (error) { return errorResponse(error, headers); }
  };
}
