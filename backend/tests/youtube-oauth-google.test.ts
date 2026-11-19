import { generateKeyPair, SignJWT, type JWTPayload } from 'jose';
import { randomBytes } from 'node:crypto';
import { describe, it, expect, vi } from 'vitest';
import { OfficialGoogleOAuth } from '../src/infrastructure/youtube/google-client.js';
import {
  digest,
  SecretBox,
  youtubeConfig,
} from '../src/infrastructure/youtube/secrets.js';
import { readScope, root } from '../src/modules/integrations/youtube/domain.js';

const config = {
  id: 'test-web',
  secret: 'test-fixture-only',
  callback: new URL('https://oauth.example.test' + root + '/oauth/callback'),
};
const nonce = 'unit-test-random-nonce';
describe('OAuth YouTube / cliente oficial', () => {
  it('configura callback fijo, openid/readonly, offline, nonce y S256; consentimiento forzado es voluntario', () => {
    const google = new OfficialGoogleOAuth(config);
    for (const consent of [true, false]) {
      const url = new URL(
        google.authorize({ state: 's', nonce, challenge: 'c', consent }),
      );
      expect(url.origin).toBe('https://accounts.google.com');
      expect(Object.fromEntries(url.searchParams)).toMatchObject({
        code_challenge_method: 'S256',
        state: 's',
        nonce,
        scope: 'openid ' + readScope,
        redirect_uri: config.callback.href,
        access_type: 'offline',
        code_challenge: 'c',
        response_type: 'code',
        prompt: consent ? 'select_account consent' : 'select_account',
      });
    }
  });
  it('verifica firma, emisor, audiencia, azp, vencimiento y nonce contra la respuesta del canje', async () => {
    const { privateKey, publicKey } = await generateKeyPair('RS256');
    const foreign = await generateKeyPair('RS256');
    const base = {
      sub: 'independent-google-sub',
      iss: 'https://accounts.google.com',
      aud: config.id,
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 300,
      nonce,
    };
    let jwt = '';
    const post = vi.fn(
      async (_url: string | URL | Request, init?: RequestInit) => {
        const form = init?.body as URLSearchParams;
        expect(form.get('code_verifier')).toBe('verifier-fixture');
        expect(form.get('redirect_uri')).toBe(config.callback.href);
        return Response.json({
          access_token: 'test-access',
          expires_in: 3600,
          token_type: 'Bearer',
          scope: 'openid ' + readScope,
          id_token: jwt,
        });
      },
    );
    const google = new OfficialGoogleOAuth(config, post, async () => publicKey);
    for (const [claims, wrongKey, valid] of [
      [{}, false, true],
      [{ iss: 'https://foreign.test' }, false, false],
      [{ aud: 'other' }, false, false],
      [{ azp: 'other' }, false, false],
      [{ aud: [config.id, 'other'] }, false, false],
      [{ exp: base.iat - 1 }, false, false],
      [{ nonce: 'other' }, false, false],
      [{}, true, false],
    ] as [JWTPayload, boolean, boolean][]) {
      jwt = await new SignJWT({ ...base, ...claims })
        .setProtectedHeader({ alg: 'RS256' })
        .sign(wrongKey ? foreign.privateKey : privateKey);
      const op = google.exchange('code', 'verifier-fixture', digest(nonce));
      if (valid) await expect(op).resolves.toMatchObject({ subject: base.sub });
      else
        await expect(op).rejects.toMatchObject({
          code: 'INVALID_GOOGLE_IDENTITY',
        });
    }
  });
  it('clasifica invalid_grant y errores transitorios; una revocación ya cumplida es idempotente', async () => {
    const bad = (reason: string, status: number) =>
      new OfficialGoogleOAuth(config, async () =>
        Response.json({ error: reason }, { status }),
      );
    await expect(
      bad('invalid_grant', 400).refresh('fixture'),
    ).rejects.toMatchObject({ code: 'INVALID_GRANT' });
    await expect(
      bad('internal_error', 503).refresh('fixture'),
    ).rejects.toMatchObject({ status: 503 });
    await expect(
      bad('invalid_token', 400).revoke('fixture'),
    ).resolves.toBeUndefined();
    await expect(
      bad('internal_error', 503).revoke('fixture'),
    ).rejects.toMatchObject({ code: 'REVOCATION_PENDING' });
  });
  it('no escoge el primer canal ante ambigüedad y distingue canal vacío y cuota', async () => {
    const client = (body: unknown, status = 200) =>
      new OfficialGoogleOAuth(config, async () =>
        Response.json(body, { status }),
      );
    const item = { id: 'channel', snippet: { title: 'Canal' } };
    await expect(
      client({ items: [] }).channel('fixture'),
    ).rejects.toMatchObject({ code: 'NO_CHANNEL' });
    await expect(
      client({ items: [item], nextPageToken: 'next' }).channel('fixture'),
    ).rejects.toMatchObject({ code: 'SELECT_CHANNEL_IN_GOOGLE' });
    await expect(client({ items: [item] }).channel('fixture')).resolves.toEqual(
      { id: 'channel', title: 'Canal' },
    );
    await expect(
      client({ error: { errors: [{ reason: 'quotaExceeded' }] } }, 403).channel(
        'fixture',
      ),
    ).rejects.toMatchObject({ code: 'YOUTUBE_QUOTA' });
  });
  it('rota claves y autentica contexto y contenido del sobre', () => {
    const key = randomBytes(32),
      next = randomBytes(32);
    const first = new SecretBox('v1', new Map([['v1', key]]));
    const rotated = new SecretBox(
      'v2',
      new Map([
        ['v1', key],
        ['v2', next],
      ]),
    );
    const box = first.seal('dato de prueba', 'propietario A');
    expect(rotated.open(box, 'propietario A')).toBe('dato de prueba');
    expect(() => rotated.open(box, 'propietario B')).toThrow();
    expect(() => rotated.open(box + 'AAA', 'propietario A')).toThrow();
    expect(rotated.seal('dato de prueba', 'propietario A')).toMatch(/^v2\./);
    expect(youtubeConfig({})).toBeNull();
    expect(() => youtubeConfig({ YOUTUBE_LINK_ENABLED: 'true' })).toThrow();
  });
});
