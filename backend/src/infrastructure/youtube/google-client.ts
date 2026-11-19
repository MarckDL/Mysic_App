import { YoutubeDataLibraryProvider } from './youtube-data-library-provider.js';
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import { z } from 'zod';
import { digest } from './secrets.js';
import {
  LinkError,
  readScope,
  type GoogleOAuthClient,
  type Tokens,
} from '../../modules/integrations/youtube/domain.js';

const issuer = 'https://accounts.google.com';
const tokenUrl = 'https://oauth2.googleapis.com/token';
const keys = createRemoteJWKSet(
  new URL('https://www.googleapis.com/oauth2/v3/certs'),
  { timeoutDuration: 5000 },
);
const tokenSchema = z.object({
  access_token: z.string().min(1),
  token_type: z.string().regex(/^bearer$/i),
  expires_in: z.number().int().positive(),
  scope: z.string().optional(),
  refresh_token: z.string().min(1).optional(),
  id_token: z.string().optional(),
});
type TokenResponse = z.infer<typeof tokenSchema>;
function tokens(data: TokenResponse): Tokens {
  return {
    access: data.access_token,
    expiresIn: data.expires_in,
    refresh: data.refresh_token,
    scope: data.scope,
  };
}
export class OfficialGoogleOAuth implements GoogleOAuthClient {
  constructor(
    private readonly config: { id: string; secret: string; callback: URL },
    private readonly transport: typeof fetch = fetch,
    private readonly signingKeys: JWTVerifyGetKey = keys,
  ) {}
  authorize(input: Parameters<GoogleOAuthClient['authorize']>[0]) {
    const url = new URL('/o/oauth2/v2/auth', issuer);
    url.search = new URLSearchParams({
      client_id: this.config.id,
      redirect_uri: this.config.callback.href,
      response_type: 'code',
      scope: 'openid ' + readScope,
      access_type: 'offline',
      prompt: input.consent ? 'select_account consent' : 'select_account',
      state: input.state,
      nonce: input.nonce,
      code_challenge: input.challenge,
      code_challenge_method: 'S256',
    }).toString();
    return url.href;
  }
  private async request(url: string, init: RequestInit) {
    try {
      return await this.transport(url, {
        ...init,
        redirect: 'error',
        signal: AbortSignal.timeout(7000),
      });
    } catch {
      throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
    }
  }
  private async token(fields: Record<string, string>) {
    const res = await this.request(tokenUrl, {
      method: 'POST',
      body: new URLSearchParams({
        ...fields,
        client_id: this.config.id,
        client_secret: this.config.secret,
      }),
    });
    const json = await res.json().catch(() => null);
    if (!res.ok) {
      if (json?.error === 'invalid_grant')
        throw new LinkError(409, 'INVALID_GRANT');
      throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
    }
    const data = tokenSchema.safeParse(json);
    if (!data.success) throw new LinkError(503, 'GOOGLE_INVALID_RESPONSE');
    return data.data;
  }
  async exchange(code: string, verifier: string, nonceHash: string) {
    const data = await this.token({
      grant_type: 'authorization_code',
      code,
      code_verifier: verifier,
      redirect_uri: this.config.callback.href,
    });
    try {
      const { payload } = await jwtVerify(
        data.id_token ?? '',
        this.signingKeys,
        {
          issuer: [issuer, 'accounts.google.com'],
          audience: this.config.id,
          algorithms: ['RS256'],
          requiredClaims: ['exp', 'iat', 'sub', 'nonce'],
        },
      );
      if (
        typeof payload.sub !== 'string' ||
        !payload.sub ||
        typeof payload.nonce !== 'string' ||
        digest(payload.nonce) !== nonceHash ||
        (payload.azp !== undefined && payload.azp !== this.config.id) ||
        (Array.isArray(payload.aud) &&
          payload.aud.length > 1 &&
          payload.azp !== this.config.id)
      )
        throw new Error();
      return { ...tokens(data), subject: payload.sub };
    } catch (error) {
      if (
        error instanceof TypeError ||
        (error instanceof Error &&
          'code' in error &&
          ['ERR_JWKS_TIMEOUT', 'ERR_JOSE_GENERIC'].includes(String(error.code)))
      )
        throw new LinkError(503, 'GOOGLE_UNAVAILABLE');
      throw new LinkError(409, 'INVALID_GOOGLE_IDENTITY');
    }
  }
  async channel(access: string) {
    const library = new YoutubeDataLibraryProvider(this.transport);
    try {
      const result = await library.listChannels({
        access,
        signal: AbortSignal.timeout(7000),
      });
      const first = result.items[0];
      if (!first) throw new LinkError(409, 'NO_CHANNEL');
      if (result.items.length !== 1 || result.nextPageToken)
        throw new LinkError(409, 'SELECT_CHANNEL_IN_GOOGLE');
      return first;
    } catch (err) {
      if (err instanceof LinkError && err.code === 'YOUTUBE_ACCESS_REJECTED')
        throw new LinkError(409, 'INVALID_GRANT');
      if (err instanceof LinkError && err.code === 'MISSING_SCOPE')
        throw new LinkError(409, 'MISSING_SCOPE');
      throw err;
    }
  }
  async refresh(token: string) {
    return tokens(
      await this.token({ grant_type: 'refresh_token', refresh_token: token }),
    );
  }
  async revoke(token: string) {
    const res = await this.request('https://oauth2.googleapis.com/revoke', {
      method: 'POST',
      body: new URLSearchParams({ token }),
    });
    if (res.ok) return;
    const data = await res.json().catch(() => null);
    if (res.status === 400 && data?.error === 'invalid_token') return;
    throw new LinkError(503, 'REVOCATION_PENDING');
  }
}
