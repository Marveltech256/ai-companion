export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export function publicError(error: unknown): ApiError {
  return error instanceof ApiError ? error :
    new ApiError(500, "internal_error", "Connection unavailable. Please try again.");
}

export function requiredString(value: unknown, name: string, max = 200): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) {
    throw new ApiError(400, "invalid_input", `Invalid ${name}.`);
  }
  return value.trim();
}

export function uuid(value: unknown): string {
  const result = requiredString(value, "identifier", 36);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result)) {
    throw new ApiError(400, "invalid_input", "Invalid identifier.");
  }
  return result;
}
