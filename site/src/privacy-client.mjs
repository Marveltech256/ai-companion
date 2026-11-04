export async function privacyRequest(config,token,action,body={},fetcher=fetch){
 const response=await fetcher(`${config.supabaseUrl}/functions/v1/privacy`,{method:'POST',headers:{
  'Content-Type':'application/json',apikey:config.publishableKey,Authorization:`Bearer ${token}`},
  body:JSON.stringify({action,...body}),signal:AbortSignal.timeout(20000)});
 const result=await response.json().catch(()=>({}));
 if(!response.ok)throw new Error(result.message||'Your request could not be completed. Please try again.');
 return result;
}
