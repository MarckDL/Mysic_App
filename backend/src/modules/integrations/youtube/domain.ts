export const root = '/api/v1/integrations/youtube';
export const readScope = 'https://www.googleapis.com/auth/youtube.readonly';
export const ttl = 10 * 60_000;
export class LinkError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    public readonly retryAfter?: number,
  ) {
    super(code);
  }
}
export interface Tokens {
  access: string;
  expiresIn: number;
  refresh?: string;
  scope?: string;
}
export interface Grant extends Tokens {
  subject: string;
}
export interface GoogleOAuthClient {
  authorize(input: {
    state: string;
    nonce: string;
    challenge: string;
    consent: boolean;
  }): string;
  exchange(code: string, verifier: string, nonceHash: string): Promise<Grant>;
  channel(access: string): Promise<{ id: string; title: string }>;
  refresh(token: string): Promise<Tokens>;
  revoke(token: string): Promise<void>;
}
