import {test} from 'node:test';
import assert from 'node:assert/strict';
import {privacyRequest} from '../../site/src/privacy-client.mjs';

test('public deletion client sends only explicit confirmation with the current Firebase identity',async()=>{
 let sent:any;
 const result=await privacyRequest({supabaseUrl:'https://project.example',publishableKey:'public-key'},'synthetic-token',
  'request_account_erasure',{confirmation:'DELETE_MY_ACCOUNT'},async(url:any,options:any)=>{
   sent={url,...options};return Response.json({status:'pending'},{status:202});
  });
 assert.equal(result.status,'pending');assert.equal(sent.url,'https://project.example/functions/v1/privacy');
 assert.equal(sent.headers.Authorization,'Bearer synthetic-token');
 assert.deepEqual(JSON.parse(sent.body),{action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'});
 await assert.rejects(privacyRequest({supabaseUrl:'https://project.example',publishableKey:'public'},'token','erasure_status',{},
  async()=>new Response('gateway unavailable',{status:503})),/could not be completed/);
});

