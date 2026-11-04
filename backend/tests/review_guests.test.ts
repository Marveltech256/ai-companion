import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {generateKeyPair,exportPKCS8,jwtVerify} from 'jose';
import {database,rpc} from './database.ts';
import {createReviewAccess,createReviewSigner,guardReviewIdentity,reviewCodeHash} from '../../supabase/functions/_shared/review_access.ts';
import {ApiError} from '../../supabase/functions/_shared/errors.ts';
import {createPrivacyApi} from '../../supabase/functions/_shared/privacy.ts';

test('a deleted review guest can poll only its erasure receipt without reopening protected data',async()=>{
 const api=createPrivacyApi({projectId:'project',origins:[],
  verify:async()=>({uid:'review_deleted',anonymous:false,reviewGuest:true,reviewVersion:randomUUID()}),
  guardIdentity:async()=>{throw new ApiError(401,'review_access_ended','Review access ended.');},
  admin:{async active(){throw Error('Deleted Firebase account must not be loaded for status');},async erase(){}},
  db:{async rpc<T>(name:string,args:any):Promise<T>{assert.equal(name,'morrow_account_status');assert.equal(args.p_owner,'review_deleted');return{status:'complete'} as T;}}});
 const request=(action:string)=>new Request('https://edge.example',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,section:'profile'})});
 assert.equal((await api(request('erasure_status'))).status,200);
 assert.equal((await api(request('export_data'))).status,401);
});

test('review sessions are private, independently owned and immediately revoked by the SQL switch',async()=>{
 const db=await database();try{
  const first=`review_${randomUUID()}`,second=`review_${randomUUID()}`;
  const status=await rpc<any>(db,'morrow_review_status',{});assert.equal(status.enabled,false);
  await assert.rejects(rpc(db,'morrow_review_begin',{p_owner:first,p_version:status.version}),/review_access_ended/);
  await db.exec('update public.review_configuration set enabled=true');
  for(const owner of [first,second]){
   await rpc(db,'morrow_review_begin',{p_owner:owner,p_version:status.version});await rpc(db,'morrow_bootstrap',{p_owner:owner});
   await rpc(db,'morrow_review_guard',{p_owner:owner,p_version:status.version});
  }
  const claims=(owner:string,extra={})=>({iss:'https://securetoken.google.com/morrow',sub:owner,
   firebase:{sign_in_provider:'custom'},review_guest:true,review_version:status.version,...extra});
  async function readable(value:any){
   await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify(value)]);await db.exec('set role authenticated');
   try{return (await db.query<{user_id:string}>('select user_id from public.profiles')).rows.map(r=>r.user_id);}finally{await db.exec('reset role');}
  }
  assert.deepEqual(await readable(claims(first)),[first]);assert.deepEqual(await readable(claims(second)),[second]);
  assert.deepEqual(await readable(claims(first,{review_guest:false})),[]);
  assert.deepEqual(await readable(claims(first,{review_version:randomUUID()})),[]);
  await db.exec('set role authenticated');await assert.rejects(db.query('select * from public.review_guest_sessions'),/permission denied/);
  await assert.rejects(db.query('select public.morrow_review_status()'),/permission denied/);await db.exec('reset role');
  await db.exec('update public.review_configuration set enabled=false');
  assert.deepEqual(await readable(claims(first)),[]);
  await assert.rejects(rpc(db,'morrow_review_guard',{p_owner:first,p_version:status.version}),/review_access_ended/);
  const cleaned=await rpc<any>(db,'morrow_review_cleanup',{});assert.equal(cleaned.queued,2);
  const deletion=await rpc<any>(db,'morrow_claim_erasure',{p_owner:first});
  await rpc(db,'morrow_erase_application_data',{p_owner:first,p_lease:deletion.job.lease});
  assert.equal((await db.query('select count(*)::int n from public.review_guest_sessions where owner_id=$1',[first])).rows[0].n,0);
 }finally{await db.close();}
});

test('old inactive review workspaces queue deletion without affecting ordinary accounts',async()=>{
 const db=await database();try{
  const owner=`review_${randomUUID()}`,status=await rpc<any>(db,'morrow_review_status',{});
  await db.exec('update public.review_configuration set enabled=true');
  await rpc(db,'morrow_review_begin',{p_owner:owner,p_version:status.version});
  await rpc(db,'morrow_bootstrap',{p_owner:owner});await rpc(db,'morrow_bootstrap',{p_owner:'ordinary'});
  await db.exec("update public.review_guest_sessions set last_seen_at=now()-interval '31 days'");
  assert.equal((await rpc<any>(db,'morrow_review_cleanup',{})).queued,1);
  assert.equal((await rpc<any>(db,'morrow_account_status',{p_owner:'ordinary'})).blocked,false);
 }finally{await db.close();}
});

test('review entry is off by default, requires its code and ignores forged owners; renewal binds the verified reviewer',async()=>{
 const code='a synthetic review-only code',version=randomUUID(),events:string[]=[];
 let owner='',enabled=true;
 const deps={enabled:true,codeHash:await reviewCodeHash(code),origins:['https://app.example'],
  db:{async rpc<T>(name:string,args:any):Promise<T>{events.push(name);if(name==='morrow_review_status')return{enabled,version} as T;
   if(name==='morrow_review_begin')owner=args.p_owner;return {ok:true} as T;}},
  admin:{async active(){},async erase(){}},verifyToken:async()=>({uid:owner,anonymous:false,reviewGuest:true,reviewVersion:version}),
  sign:async(uid:string,v:string)=>{assert.equal(v,version);return `synthetic-token-for-${uid}`;}};
 const request=(body:any)=>new Request('https://edge.example',{method:'POST',headers:{'Content-Type':'application/json',Origin:'https://app.example'},body:JSON.stringify(body)});
 const closed=createReviewAccess({...deps,enabled:false});assert.equal((await closed(request({action:'enter',access_code:code}))).status,503);assert.equal(events.length,0);
 const api=createReviewAccess(deps);const status=await(await api(request({action:'status'}))).json();assert.deepEqual(status,{enabled:true});
 assert.equal((await api(request({action:'enter',access_code:'wrong',owner_id:'victim'}))).status,401);assert.equal(owner,'');
 const result=await(await api(request({action:'enter',access_code:code,owner_id:'victim'}))).json();
 assert.match(owner,/^review_[0-9a-f-]{36}$/);assert.equal(result.custom_token,`synthetic-token-for-${owner}`);
 const first=owner;await api(request({action:'enter',access_code:code,renew:true,owner_id:'victim'}));assert.equal(owner,first);
 const ordinary=createReviewAccess({...deps,verifyToken:async()=>({uid:'ordinary',anonymous:false})});
 assert.equal((await ordinary(request({action:'enter',access_code:code,renew:true}))).status,403);
 enabled=false;assert.equal((await api(request({action:'enter',access_code:code}))).status,503);
 await assert.rejects(guardReviewIdentity(deps.db,{uid:'review_missing',anonymous:false}),/ended/);
});

test('custom review tokens have the correct Firebase audience and scoped additional claims',async()=>{
 const {privateKey,publicKey}=await generateKeyPair('RS256',{extractable:true});
 const email='review-signer@project.iam.gserviceaccount.com',uid=`review_${randomUUID()}`,version=randomUUID();
 const sign=createReviewSigner(JSON.stringify({project_id:'project',client_email:email,private_key:await exportPKCS8(privateKey)}),'project');
 const {payload}=await jwtVerify(await sign(uid,version),publicKey,{issuer:email,subject:email,
  audience:'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit'});
 assert.equal(payload.uid,uid);assert.deepEqual(payload.claims,{review_guest:true,review_version:version});assert.ok(payload.exp!-payload.iat!<=3600);
 await assert.rejects(createReviewSigner('{}','project')(uid,version),(e:unknown)=>e instanceof ApiError&&e.code==='review_unavailable');
});
