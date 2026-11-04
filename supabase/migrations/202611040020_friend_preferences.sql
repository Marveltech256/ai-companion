-- Extend the existing owned companion; preserve accounts, names, consent and history.
alter table public.companions
 add column personality_keys text[] not null default '{}' check(cardinality(personality_keys)<=2 and array_position(personality_keys,null) is null
  and personality_keys <@ array['warm_caring','funny_playful','calm_understanding','positive_motivating','curious_intellectual','friendly_outgoing','wise_thoughtful','casual_relaxed']::text[]),
 add column support_preferences text[] not null default '{}' check(cardinality(support_preferences)<=4 and array_position(support_preferences,null) is null
  and support_preferences <@ array['emotional_support','daily_companionship','motivation','personal_growth','learning','friendship','productivity','perspectives','creativity','relaxation','language_practice','confidence']::text[]),
 add column interaction_style text check(interaction_style in ('casual_natural','warm_affectionate','calm_gentle','funny_playful','direct','thoughtful_detailed')),
 add column learning_interests text not null default '' check(length(learning_interests)<=400),
 add column personal_goals text not null default '' check(length(personal_goals)<=600),
 add column additional_information text not null default '' check(length(additional_information)<=600),
 add column preferences_completed_at timestamptz;

-- Legacy settings remain effective until the owner explicitly chooses new preferences.
create function public.morrow_save_friend_preferences(p_owner text,p_companion uuid,p_name text,
 p_personalities text[],p_support text[],p_communication text,p_learning text,p_goals text,p_additional text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 perform public.morrow_require_eligible(p_owner);
 if p_name is null or length(btrim(p_name)) not between 1 and 24 or p_name ~ '[[:cntrl:]]'
  or p_personalities is null or cardinality(p_personalities) not between 1 and 2
  or cardinality(p_personalities)<>(select count(distinct value) from unnest(p_personalities) value)
  or p_support is null or cardinality(p_support)>4
  or cardinality(p_support)<>(select count(distinct value) from unnest(p_support) value)
  or p_communication is null or p_learning is null or p_goals is null or p_additional is null
 then raise exception 'invalid_input'; end if;
 update public.companions set name=btrim(p_name),personality_keys=p_personalities,
  support_preferences=p_support,interaction_style=p_communication,learning_interests=btrim(p_learning),
  personal_goals=btrim(p_goals),additional_information=btrim(p_additional),
  preferences_completed_at=coalesce(preferences_completed_at,now()),updated_at=now()
  where id=p_companion and owner_id=p_owner returning to_jsonb(companions.*) into result;
 if result is null then raise exception 'not_found'; end if;
 return jsonb_build_object('companion',result);
end; $$;
revoke all on function public.morrow_save_friend_preferences(text,uuid,text,text[],text[],text,text,text,text) from public,anon,authenticated;
grant execute on function public.morrow_save_friend_preferences(text,uuid,text,text[],text[],text,text,text,text) to service_role;
