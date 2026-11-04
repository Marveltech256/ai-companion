import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, SignJWT } from 'jose';
import { verifyFirebase, requireRegisteredIdentity } from '../../supabase/functions/_shared/auth.ts';
import { createCompanionApi } from '../../supabase/functions/_shared/companion_api.ts';

test('Firebase verifier rejects expired and wrong-project tokens', async () => {
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const token = (project: string, expiry: number, firebase?:Record<string,unknown>) => new SignJWT({auth_time:Math.floor(Date.now()/1000),...(firebase?{firebase}:{})})
    .setProtectedHeader({alg:'RS256',kid:'test'}).setSubject('alice')
    .setAudience(project).setIssuer(`https://securetoken.google.com/${project}`)
    .setIssuedAt().setExpirationTime(expiry).sign(privateKey);
  const req = (jwt: string) => new Request('https://local.test',{headers:{Authorization:`Bearer ${jwt}`}});
  const keys = async () => publicKey;
  const future = Math.floor(Date.now()/1000)+60;
  assert.equal((await verifyFirebase(req(await token('morrow',future)),'morrow',keys)).uid,'alice');
  await assert.rejects(verifyFirebase(req(await token('other',future)),'morrow',keys));
  await assert.rejects(verifyFirebase(req(await token('morrow',1)),'morrow',keys));
  await assert.rejects(verifyFirebase(req('forged'),'morrow',keys));
  await assert.rejects(verifyFirebase(req(await token('morrow',future,{tenant:'unsupported-tenant'})),'morrow',keys));
  const guest=await verifyFirebase(req(await token('morrow',future,{sign_in_provider:'anonymous'})),'morrow',keys);
  assert.throws(()=>requireRegisteredIdentity(guest),/Sign in to continue/);
  for(const sign_in_provider of ['password','google.com']){
    const identity=await verifyFirebase(req(await token('morrow',future,{sign_in_provider})),'morrow',keys);
    assert.equal(requireRegisteredIdentity(identity).uid,'alice');
  }
  assert.throws(()=>requireRegisteredIdentity({uid:'alice'}),/Sign in to continue/);
});

test('API uses verified identity rather than body-supplied ownership', async () => {
  let observed: Record<string,unknown> = {};
  const handler = createCompanionApi({ origins:['https://morrow.test'],
    verify:async()=>({uid:'alice'}), db:{rpc:async <T>(_name:string,args:Record<string,unknown>)=>{
      observed=args; return {} as T;
    }}});
  const response=await handler(new Request('https://local.test',{method:'POST',
    headers:{'Content-Type':'application/json',Origin:'https://morrow.test'},
    body:JSON.stringify({action:'bootstrap',p_owner:'bob',owner_id:'bob'})}));
  assert.equal(response.status,200); assert.equal(observed.p_owner,'alice');
  const denied=await handler(new Request('https://local.test',{method:'OPTIONS',
    headers:{Origin:'https://evil.test'}}));
  assert.equal(denied.status,403);
});
