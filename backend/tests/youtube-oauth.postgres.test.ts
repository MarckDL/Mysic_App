import { randomBytes, randomUUID } from 'node:crypto';
import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import {
  getDatabase,
  disconnectDatabase,
} from '../src/infrastructure/database/prisma.js';
import {
  digest,
  randomRef,
  SecretBox,
} from '../src/infrastructure/youtube/secrets.js';
import { OfficialGoogleOAuth } from '../src/infrastructure/youtube/google-client.js';
import {
  root,
  readScope,
  LinkError,
  type Tokens,
} from '../src/modules/integrations/youtube/domain.js';
import { YoutubeGrants } from '../src/modules/integrations/youtube/grants.js';
import { YoutubeLinkService } from '../src/modules/integrations/youtube/link-service.js';

const callback = new URL('https://api.example.test' + root + '/oauth/callback');
const appReturn = new URL('https://app.example.test/library/youtube/return');
const keyring = new SecretBox('test', new Map([['test', randomBytes(32)]]));
const prefix = randomUUID();
const grant = () => ({
  subject: prefix + '-yt',
  access: randomRef(),
  refresh: randomRef(),
  expiresIn: 3600,
  scope: 'openid ' + readScope,
});
const oauth = new OfficialGoogleOAuth({
  id: 'fixture',
  secret: randomRef(),
  callback,
});
const provider = {
  authorize: oauth.authorize.bind(oauth),
  exchange: vi.fn(
    async (_code: string, _verifier: string, _nonceHash: string) => grant(),
  ),
  channel: vi.fn(async (_access: string) => ({
    id: 'channel',
    title: 'Canal verificado',
  })),
  refresh: vi.fn(async (_refresh: string): Promise<Tokens> => ({
    access: randomRef(),
    expiresIn: 3600,
  })),
  revoke: vi.fn(async (_token: string) => {}),
};
const grants = new YoutubeGrants(keyring, provider);
const svc = new YoutubeLinkService(grants, callback, appReturn, true);
const disabled = new YoutubeLinkService(grants, callback, appReturn, false);
const uidA = prefix + '-a',
  uidB = prefix + '-b';
const app = createApp({
  youtubeLinkService: svc,
  tokenVerifier: {
    async verify(uid) {
      return {
        firebaseUid: uid,
        googleId: 'firebase-sub-' + uid,
        provider: 'google.com',
      };
    },
  },
});
let a: string, b: string;
async function launch(owner: string, key = randomUUID()) {
  const started = await svc.start(owner, key, false);
  const opened = await svc.begin(
    new URL(started.launchUrl!).searchParams.get('ref')!,
  );
  const query = new URL(opened.url).searchParams;
  return {
    id: started.attemptId,
    state: query.get('state')!,
    cookie: opened.cookie,
    challenge: query.get('code_challenge'),
    nonce: query.get('nonce'),
  };
}
async function candidate(owner: string) {
  const x = await launch(owner);
  const ret = new URL(await svc.finish(x.state, x.cookie, 'test-only-code'));
  return {
    ...x,
    ref: new URLSearchParams(ret.hash.slice(1)).get('returnRef')!,
  };
}
async function link(owner: string) {
  const x = await candidate(owner);
  await svc.confirm(owner, x.id, { returnRef: x.ref });
  return x;
}
describe.skipIf(!process.env.TEST_DATABASE_URL)(
  'OAuth YouTube en PostgreSQL',
  () => {
    beforeAll(async () => {
      process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
      a = (
        await getDatabase().user.create({
          data: { firebaseUid: uidA, displayName: 'A' },
        })
      ).id;
      b = (
        await getDatabase().user.create({
          data: { firebaseUid: uidB, displayName: 'B' },
        })
      ).id;
    });
    beforeEach(async () => {
      await getDatabase().externalMusicLinkAttempt.deleteMany({
        where: { userId: { in: [a, b] } },
      });
      await getDatabase().externalMusicConnection.deleteMany({
        where: { userId: { in: [a, b] } },
      });
      await getDatabase().externalMusicRevocationJob.deleteMany({
        where: { ownerId: { in: [a, b] } },
      });
      vi.clearAllMocks();
    });
    afterAll(async () => {
      await getDatabase().externalMusicRevocationJob.deleteMany({
        where: { ownerId: { in: [a, b] } },
      });
      await getDatabase().user.deleteMany({
        where: { firebaseUid: { in: [uidA, uidB] } },
      });
      await disconnectDatabase();
    });
    it('solo el titular cancela su intento y conserva su canal conectado', async () => {
      await link(a);
      const original = await svc.connection(a);
      const attempt = await candidate(a);
      const path = root + '/link-attempts/' + attempt.id;
      await request(app).delete(path).expect(401);
      await request(app)
        .delete(path)
        .set('Authorization', 'Bearer ' + uidB)
        .expect(404);
      for (let i = 0; i < 2; i++)
        await request(app)
          .delete(path)
          .set('Authorization', 'Bearer ' + uidA)
          .expect(204);
      expect((await svc.attempt(a, attempt.id)).status).toBe('canceled');
      expect(await svc.connection(a)).toEqual(original);
      expect(provider.revoke).not.toHaveBeenCalled();
    });
    it('retira el permiso provisional cuando se cancela antes de vincular', async () => {
      const attempt = await candidate(a);
      await svc.cancel(a, attempt.id);
      expect(provider.revoke).toHaveBeenCalledTimes(1);
      expect((await svc.connection(a)).status).toBe('unlinked');
    });
    it('rutas reales: Firebase, cookie del navegador, PKCE, retorno opaco, confirmación y revocación', async () => {
      await request(app)
        .post(root + '/link-attempts')
        .send({})
        .expect(401);
      const post = await request(app)
        .post(root + '/link-attempts')
        .set('Authorization', 'Bearer ' + uidA)
        .send({})
        .expect(201);
      const opened = await request(app)
        .get(
          new URL(post.body.launchUrl).pathname +
            new URL(post.body.launchUrl).search,
        )
        .expect(302);
      const cookie = String(opened.headers['set-cookie']?.[0]);
      expect(cookie).toMatch(/HttpOnly/);
      expect(cookie).toMatch(/Secure/);
      expect(cookie).toMatch(/SameSite=Lax/);
      const query = new URL(opened.headers.location!).searchParams;
      const fixture = grant();
      provider.exchange.mockImplementationOnce(
        async (_code, verifier, nonceHash) => {
          expect(digest(verifier)).toBe(query.get('code_challenge'));
          expect(nonceHash).toBe(digest(query.get('nonce')!));
          return fixture;
        },
      );
      const ret = await request(app)
        .get(root + '/oauth/callback')
        .query({ state: query.get('state'), code: 'provider-code' })
        .set('Cookie', cookie.split(';')[0]!)
        .expect(200);
      expect(ret.headers['cache-control']).toBe('no-store');
      expect(ret.headers['referrer-policy']).toBe('no-referrer');
      const ref = ret.text.match(/returnRef=([A-Za-z0-9_-]{43})/)?.[1];
      expect(ref).toBeTruthy();
      const path = root + '/link-attempts/' + post.body.attemptId;
      await request(app)
        .get(path)
        .set('Authorization', 'Bearer ' + uidB)
        .expect(404);
      await request(app)
        .post(path + '/confirm')
        .set('Authorization', 'Bearer ' + uidB)
        .send({ returnRef: ref })
        .expect(404);
      for (let i = 0; i < 2; i++)
        await request(app)
          .post(path + '/confirm')
          .set('Authorization', 'Bearer ' + uidA)
          .send({ returnRef: ref })
          .expect(200);
      const conn = await request(app)
        .get(root + '/connection')
        .set('Authorization', 'Bearer ' + uidA)
        .expect(200);
      expect(conn.body).toMatchObject({
        status: 'linked',
        channel: { id: 'channel' },
      });
      const row = await getDatabase().externalMusicConnection.findUniqueOrThrow(
        { where: { userId: a } },
      );
      expect(row.subject).toBe(fixture.subject);
      for (const secret of [fixture.access, fixture.refresh, 'provider-code'])
        expect(JSON.stringify([row, conn.body, ret.text])).not.toContain(
          secret,
        );
      await request(app)
        .delete(root + '/connection')
        .set('Authorization', 'Bearer ' + uidA)
        .expect(204);
      expect(provider.revoke).toHaveBeenCalledWith(fixture.refresh);
      expect((await svc.connection(a)).status).toBe('unlinked');
    });
    it('reintento idempotente, inicio único, state/cookie incorrectos y callback repetido', async () => {
      const key = randomUUID();
      const [first, second] = await Promise.all([
        svc.start(a, key, false),
        svc.start(a, key, false),
      ]);
      expect(first).toEqual(second);
      const ref = new URL(first.launchUrl!).searchParams.get('ref')!;
      const x = await svc.begin(ref);
      await expect(svc.begin(ref)).rejects.toMatchObject({
        code: 'STALE_ATTEMPT',
      });
      const state = new URL(x.url).searchParams.get('state')!;
      await expect(
        svc.finish(randomRef(), x.cookie, 'code'),
      ).rejects.toMatchObject({ code: 'STALE_ATTEMPT' });
      await expect(
        svc.finish(state, randomRef(), 'code'),
      ).rejects.toMatchObject({ code: 'STALE_ATTEMPT' });
      await svc.finish(state, x.cookie, 'code');
      await expect(svc.finish(state, x.cookie, 'code')).rejects.toMatchObject({
        code: 'STALE_ATTEMPT',
      });
      expect(provider.exchange).toHaveBeenCalledTimes(1);
      expect((await svc.start(a, key, false)).launchUrl).toBeNull();
    });
    it('consentimiento denegado, falta de permiso, falta de refresh, error temporal y canal ausente', async () => {
      for (const reason of [
        'ACCESS_DENIED',
        'MISSING_SCOPE',
        'MISSING_REFRESH_TOKEN',
        'GOOGLE_UNAVAILABLE',
        'NO_CHANNEL',
      ]) {
        const x = await launch(a);
        if (reason === 'MISSING_SCOPE')
          provider.exchange.mockResolvedValueOnce({
            ...grant(),
            scope: 'openid',
          });
        if (reason === 'MISSING_REFRESH_TOKEN')
          provider.exchange.mockResolvedValueOnce({
            ...grant(),
            subject: randomUUID(),
            refresh: '',
          });
        if (reason === 'GOOGLE_UNAVAILABLE')
          provider.exchange.mockRejectedValueOnce(new LinkError(503, reason));
        if (reason === 'NO_CHANNEL')
          provider.channel.mockRejectedValueOnce(new LinkError(409, reason));
        await svc.finish(
          x.state,
          x.cookie,
          reason === 'ACCESS_DENIED' ? undefined : 'code',
          reason === 'ACCESS_DENIED' ? 'access_denied' : undefined,
        );
        expect(await svc.attempt(a, x.id)).toMatchObject({
          reason,
          status: reason === 'ACCESS_DENIED' ? 'denied' : 'failed',
        });
      }
    });
    it('vence intentos, limpia sus secretos y descarta un intento anterior sin cambiar el vínculo', async () => {
      await link(a);
      const x = await launch(a);
      const y = await launch(a);
      await expect(svc.finish(x.state, x.cookie, 'code')).rejects.toMatchObject(
        { code: 'STALE_ATTEMPT' },
      );
      await getDatabase().externalMusicLinkAttempt.update({
        where: { id: y.id },
        data: { expiresAt: new Date(0) },
      });
      await expect(svc.finish(y.state, y.cookie, 'code')).rejects.toMatchObject(
        { code: 'STALE_ATTEMPT' },
      );
      await svc.maintain();
      expect(
        await getDatabase().externalMusicLinkAttempt.count({
          where: { id: y.id, verifierBox: { not: null } },
        }),
      ).toBe(0);
      expect((await svc.connection(a)).status).toBe('linked');
    });
    it('protege sujeto entre cuentas y exige confirmación explícita al reemplazar o volver manualmente', async () => {
      await link(a);
      const other = await candidate(b);
      expect(await svc.attempt(b, other.id)).toMatchObject({
        reason: 'LINK_CONFLICT',
      });
      expect(
        await getDatabase().externalMusicRevocationJob.count({
          where: { subject: prefix + '-yt' },
        }),
      ).toBe(0);
      provider.exchange.mockResolvedValueOnce({
        ...grant(),
        subject: prefix + '-second',
      });
      const x = await candidate(a);
      await expect(
        svc.confirm(a, x.id, { returnRef: randomRef() }),
      ).rejects.toMatchObject({ code: 'STALE_ATTEMPT' });
      await expect(
        svc.confirm(a, x.id, { returnRef: x.ref }),
      ).rejects.toMatchObject({ code: 'CONFIRM_REPLACEMENT' });
      await expect(
        svc.confirm(a, x.id, { channelId: 'other', replace: true }),
      ).rejects.toMatchObject({ code: 'CHANNEL_MISMATCH' });
      await svc.confirm(a, x.id, { channelId: 'channel', replace: true });
      expect(
        await getDatabase().externalMusicRevocationJob.count({
          where: { subject: prefix + '-yt' },
        }),
      ).toBe(1);
    });
    it('deduplica refresh, reutiliza caché y diferencia fallo temporal de invalid_grant', async () => {
      await link(a);
      const values = await Promise.all([
        grants.access(a),
        grants.access(a),
        grants.access(a),
      ]);
      expect(new Set(values).size).toBe(1);
      expect(await grants.access(a)).toBe(values[0]);
      expect(provider.refresh).toHaveBeenCalledTimes(1);
      provider.refresh.mockRejectedValueOnce(
        new LinkError(503, 'GOOGLE_UNAVAILABLE'),
      );
      await expect(grants.access(a, true)).rejects.toMatchObject({
        status: 503,
      });
      expect((await svc.connection(a)).status).toBe('linked');
      provider.refresh.mockRejectedValueOnce(
        new LinkError(409, 'INVALID_GRANT'),
      );
      await expect(grants.access(a, true)).rejects.toMatchObject({
        code: 'REAUTHORIZE_YOUTUBE',
      });
      expect(
        await getDatabase().externalMusicConnection.findUnique({
          where: { userId: a },
        }),
      ).toMatchObject({ refreshBox: null, status: 'reauthorization_required' });
    });
    it('un refresh en vuelo no revive un vínculo eliminado y su token rotado llega al revocador', async () => {
      await link(a);
      let done!: (token: Tokens) => void, entered!: () => void;
      const inRemote = new Promise<void>((r) => {
        entered = r;
      });
      provider.refresh.mockImplementationOnce(
        () =>
          new Promise((r) => {
            done = r;
            entered();
          }),
      );
      const pending = grants.access(a);
      await inRemote;
      expect(await svc.unlink(a)).toBe(true);
      const rotated = randomRef();
      done({ access: randomRef(), refresh: rotated, expiresIn: 3600 });
      await expect(pending).rejects.toMatchObject({
        code: 'REAUTHORIZE_YOUTUBE',
      });
      await svc.maintain();
      expect(provider.revoke).toHaveBeenCalledWith(rotated);
      expect((await svc.connection(a)).status).toBe('unlinked');
    });
    it('con flag apagado permite purga y reintento durable tras fallo de Google', async () => {
      await link(a);
      await expect(
        disabled.start(a, randomUUID(), false),
      ).rejects.toMatchObject({ code: 'LINK_DISABLED' });
      provider.revoke.mockRejectedValueOnce(
        new LinkError(503, 'REVOCATION_PENDING'),
      );
      expect(await disabled.unlink(a)).toBe(true);
      expect((await svc.connection(a)).status).toBe('revocation_pending');
      const x = await candidate(b);
      expect((await svc.attempt(b, x.id)).reason).toBe('LINK_CONFLICT');
      await getDatabase().externalMusicRevocationJob.updateMany({
        where: { ownerId: a },
        data: { nextAt: new Date(0) },
      });
      await disabled.maintain();
      expect((await svc.connection(a)).status).toBe('unlinked');
    });
    it('recupera la confirmación manual y renueva con otra instancia y la misma clave', async () => {
      const fixture = grant();
      provider.exchange.mockResolvedValueOnce(fixture);
      const attempt = await candidate(a);
      const restarted = new YoutubeLinkService(
        new YoutubeGrants(keyring, provider),
        callback,
        appReturn,
        true,
      );
      const view = await restarted.attempt(a, attempt.id);
      expect(view.status).toBe('awaiting_confirmation');
      await expect(restarted.confirm(a, attempt.id, {})).rejects.toMatchObject({
        code: 'CONFIRM_CHANNEL',
      });
      await restarted.confirm(a, attempt.id, { channelId: view.channel!.id });
      expect((await restarted.connection(a)).status).toBe('linked');
      await restarted.grants.access(a);
      expect(provider.refresh).toHaveBeenCalledWith(fixture.refresh);
    });
    it('revoca un permiso recibido después de cancelar el intento en otro proceso', async () => {
      const fixture = grant();
      const attempt = await launch(a);
      let deliver!: (value: typeof fixture) => void;
      let entered!: () => void;
      const exchanging = new Promise<void>((resolve) => {
        entered = resolve;
      });
      provider.exchange.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            deliver = resolve;
            entered();
          }),
      );
      const returnUrl = svc.finish(attempt.state, attempt.cookie, 'code');
      await exchanging;
      await disabled.unlink(a);
      deliver(fixture);
      expect(new URL(await returnUrl).hash).not.toContain('returnRef');
      expect(await svc.attempt(a, attempt.id)).toMatchObject({
        status: 'canceled',
      });
      expect((await svc.connection(a)).status).toBe('unlinked');
      expect(provider.revoke).toHaveBeenCalledWith(fixture.refresh);
    });
    it('protege las tres tablas con RLS', async () => {
      const rows = await getDatabase().$queryRaw<
        { relrowsecurity: boolean }[]
      >`SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='mysic' AND c.relname IN ('external_music_link_attempts','external_music_connections','external_music_revocations')`;
      expect(rows.map((x) => x.relrowsecurity)).toEqual([true, true, true]);
    });
  },
);
