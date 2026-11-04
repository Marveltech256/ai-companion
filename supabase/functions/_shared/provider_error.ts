import {ApiError} from './errors.ts';

/** Public-safe failure metadata; never carries a provider body or credential. */
export class ProviderError extends ApiError {
 constructor(status:number,code:string,message:string,readonly allowFallback:boolean){super(status,code,message);}
}
export const transientProviderStatus=(status:number)=>status===408||status===429||status>=500;
export function providerUnavailable():ProviderError {
 return new ProviderError(503,'ai_unavailable',"Your companion couldn't reply just now. Please try again.",true);
}
