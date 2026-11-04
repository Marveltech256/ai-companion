import { ApiError, publicError } from "./errors.ts";

export function cors(request: Request, allowed: string[]): Headers {
  const headers = new Headers({
    "Vary": "Origin", "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  });
  const origin = request.headers.get("origin");
  if (origin) {
    if (!allowed.includes(origin)) throw new ApiError(403, "origin_denied", "Origin is not allowed.");
    headers.set("Access-Control-Allow-Origin", origin);
  }
  return headers;
}

export async function jsonBody(request: Request): Promise<Record<string, unknown>> {
  if (!request.headers.get("content-type")?.includes("application/json")) {
    throw new ApiError(415, "invalid_content_type", "JSON is required.");
  }
  const data = await boundedBody(request,32768);
  try {
    const value = JSON.parse(new TextDecoder().decode(data));
    if (!value || Array.isArray(value) || typeof value !== "object") throw new Error();
    return value;
  } catch { throw new ApiError(400, "invalid_input", "Invalid request body."); }
}

export async function boundedBody(request:Request|Response,limit:number):Promise<Uint8Array>{
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError(400, "invalid_input", "A request body is required.");
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel();
      throw new ApiError(413, "request_too_large", "Please send a shorter message.");
    }
    chunks.push(value);
  }
  const data = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
  return data;
}

export function errorResponse(error: unknown, headers: Headers): Response {
  const safe = publicError(error);
  return Response.json({ code: safe.code, message: safe.message },
    { status: safe.status, headers });
}
