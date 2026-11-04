import type { Identity } from './auth.ts';
import { ApiError } from './errors.ts';
import { GoogleServiceAccount } from './google.ts';

export interface IdentityAdmin {
  active(identity:Identity,force?:boolean):Promise<void>;
  erase(uid:string):Promise<void>;
}
export class FirebaseIdentityAdmin implements IdentityAdmin {
  private users=new Map<string,{disabled?:boolean;validSince?:string;until:number}>();
  constructor(private account:GoogleServiceAccount,private fetcher=fetch){}
  private async call(action:string,body:Record<string,unknown>):Promise<Record<string,any>>{
    const token=await this.account.token('https://www.googleapis.com/auth/identitytoolkit');
    const response=await this.fetcher(`https://identitytoolkit.googleapis.com/v1/projects/${encodeURIComponent(this.account.projectId)}/accounts:${action}`,{
      method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
      body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
    const result=await response.json().catch(()=>({}));
    if(!response.ok){
      if(action==='delete'&&result.error?.message==='USER_NOT_FOUND')return {};
      throw new ApiError(503,'identity_unavailable','Account service is temporarily unavailable.');
    }
    return result;
  }
  async active(identity:Identity,force=false):Promise<void>{
    let user=this.users.get(identity.uid);
    if(force||!user||user.until<Date.now()){
      const result=await this.call('lookup',{localId:[identity.uid]});
      const found=result.users?.find((u:{localId:string})=>u.localId===identity.uid);
      if(!found)throw new ApiError(401,'session_revoked','Please sign in again.');
      user={disabled:found.disabled,validSince:found.validSince,until:Date.now()+15000};
      if(this.users.size>1000)this.users.clear();
      this.users.set(identity.uid,user);
    }
    const validSince=Number(user.validSince??0);
    if(user.disabled||!identity.authTime||!Number.isFinite(validSince)||validSince<0||identity.authTime<validSince)
      throw new ApiError(401,'session_revoked','Please sign in again.');
  }
  async erase(uid:string):Promise<void>{
    await this.call('delete',{localId:uid});this.users.delete(uid);
  }
}
