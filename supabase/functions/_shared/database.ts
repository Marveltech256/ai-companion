import { ApiError } from "./errors.ts";

export interface Database {
  rpc<T = Record<string, unknown>>(name: string, args: Record<string, unknown>): Promise<T>;
}

/** The privileged key exists ONLY in the Edge environment. Public handlers
 * inject p_owner from a verified Firebase identity, never from JSON input. */
export class PostgresApi implements Database {
  constructor(private url: string, private key: string, private fetcher = fetch) {
    if (!url || !key) throw new Error("Supabase server configuration is required");
  }
  async rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    if (!/^morrow_[a-z_]+$/.test(name)) throw new Error("Invalid RPC name");
    const response = await this.fetcher(`${this.url}/rest/v1/rpc/${name}`, {
      method: "POST", headers: { "apikey": this.key,
        "Authorization": `Bearer ${this.key}`, "Content-Type": "application/json" },
      body: JSON.stringify(args), signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      const known: Record<string, [number, string]> = {
        not_found: [404, "That item is no longer available."],
        turn_busy: [409, "A reply is already being prepared."],
        request_conflict: [409, "Please retry the original message."],
        rate_limited: [429, "Please wait a moment before sending again."],
        stale_turn: [409, "Reply interrupted. Please retry."],
        invalid_input: [400, "Please check your input."],
        introduction_required: [403, 'Confirm your age range, language and time zone before continuing. Ai Companion is for ages 18 and older.'],
        personal_companion_required:[403,'Continue with personal companion mode to use conversation memory and personalisation.'],
        subscription_required:[403,'Your introductory access has ended. Open your membership to review available plans.'],
        usage_limit:[429,'Your daily plan allowance has been reached. You can try again after the daily reset.'],
        billing_unavailable:[503,'Purchases are not available yet.'],
        invalid_purchase:[400,'This purchase could not be verified for your account.'],
        purchase_conflict:[409,'This purchase belongs to a different companion account.'],
        invalid_username: [400, 'Use 3–30 letters, numbers or underscores for your username. Start with a letter or number.'],
        username_taken: [409, 'That username is already taken. Choose another one.'],
        ambiguous_local_time: [400, 'That local time is skipped or occurs twice during a clock change. Choose a different time.'],
        outside_notification_hours: [400, 'Choose a time outside quiet hours and work or sleep boundaries, on an enabled day.'],
        conversation_started: [409, 'This conversation has already started. Reopen it to continue.'],
        consent_required: [403, "Please allow this feature before continuing."],
        account_deleted: [401, "This account is being removed."],
        review_access_ended: [401, 'Guest review access has ended. Please sign in.'],
      };
      const code = typeof error.message === "string" ? error.message : "";
      if (known[code]) throw new ApiError(known[code][0], code, known[code][1]);
      throw new ApiError(503, "database_unavailable", "Connection unavailable. Please try again.");
    }
    return await response.json() as T;
  }
}
