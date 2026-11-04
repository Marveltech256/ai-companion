import { importPKCS8,SignJWT } from 'jose';
import { ApiError } from './errors.ts';

/** Server-only OAuth; neither this JSON nor its tokens are returned to Flutter. */
export class GoogleServiceAccount {
  private cached=new Map<string,{value:string;until:number}>();
  constructor(private json:string,readonly projectId:string,private fetcher=fetch){}
  async token(scope:string):Promise<string>{
    const cached=this.cached.get(scope);
    if(cached && cached.until>Date.now()+60000)return cached.value;
    let account:{project_id:string;client_email:string;private_key:string};
    try{account=JSON.parse(this.json);}catch{throw new ApiError(503,'firebase_admin_not_configured','Service is not connected yet.');}
    if(account.project_id!==this.projectId||!account.client_email||!account.private_key)
      throw new ApiError(503,'firebase_admin_not_configured','Service is not connected yet.');
    const key=await importPKCS8(account.private_key,'RS256');
    const assertion=await new SignJWT({scope}).setProtectedHeader({alg:'RS256'})
      .setIssuer(account.client_email).setAudience('https://oauth2.googleapis.com/token')
      .setIssuedAt().setExpirationTime('5m').sign(key);
    const response=await this.fetcher('https://oauth2.googleapis.com/token',{method:'POST',
      headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),
      signal:AbortSignal.timeout(15000)});
    if(!response.ok){await response.body?.cancel();throw new ApiError(503,'firebase_unavailable','Service is temporarily unavailable.');}
    const result=await response.json();
    if(typeof result.access_token!=='string')throw new Error('Missing server token');
    this.cached.set(scope,{value:result.access_token,until:Date.now()+Math.min(Number(result.expires_in)||300,3600)*1000});
    return result.access_token;
  }
}
