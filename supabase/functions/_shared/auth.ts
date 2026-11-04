import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import { ApiError } from "./errors.ts";

const googleKeys = createRemoteJWKSet(new URL(
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
));

export interface Identity { uid: string;authTime?:number;issuedAt?:number;anonymous?:boolean;reviewGuest?:boolean;reviewVersion?:string }

export function requireRegisteredIdentity(identity: Identity): Identity {
  if (identity.anonymous !== false) {
    throw new ApiError(401, 'sign_in_required', 'Sign in to continue.');
  }
  return identity;
}

export async function verifyFirebase(
  request: Request, projectId: string, keys: JWTVerifyGetKey = googleKeys,
): Promise<Identity> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ") || !projectId) {
    throw new ApiError(401, "unauthenticated", "Please reconnect your session.");
  }
  try {
    const { payload } = await jwtVerify(authorization.slice(7), keys, {
      algorithms: ["RS256"], audience: projectId,
      issuer: `https://securetoken.google.com/${projectId}`,
      requiredClaims: ["sub", "iat", "exp", "auth_time"],
      clockTolerance: 5,
    });
    if (typeof payload.sub!=='string' || !payload.sub || payload.sub.length > 128 ||
        (payload.firebase as {tenant?:string}|undefined)?.tenant != null ||
        typeof payload.auth_time !== "number" || !Number.isFinite(payload.auth_time) || payload.auth_time<=0 || payload.auth_time > Date.now() / 1000 + 5 ||
        typeof payload.iat !== "number" || !Number.isFinite(payload.iat) || payload.iat<=0 || payload.iat > Date.now() / 1000 + 5) {
      throw new Error("Invalid identity claims");
    }
    return { uid: payload.sub,authTime:payload.auth_time as number,issuedAt:payload.iat,
      ...(payload.review_guest===true?{reviewGuest:true,reviewVersion:typeof payload.review_version==='string'?payload.review_version:undefined}:{}),
      anonymous:typeof (payload.firebase as {sign_in_provider?:string}|undefined)?.sign_in_provider==='string'
        ? (payload.firebase as {sign_in_provider:string}).sign_in_provider==='anonymous' : undefined };
  } catch {
    throw new ApiError(401, "unauthenticated", "Please reconnect your session.");
  }
}
