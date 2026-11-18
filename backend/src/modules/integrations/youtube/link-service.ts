import { randomUUID } from 'node:crypto';
import type { ExternalMusicLinkAttempt } from '../../../generated/prisma/client.js';
import { getDatabase } from '../../../infrastructure/database/prisma.js';
import {
  youtubeWrite,
  type YoutubeTx,
} from '../../../infrastructure/database/prisma-youtube-connection-repository.js';
import { randomRef, digest } from '../../../infrastructure/youtube/secrets.js';
import { LinkError, readScope, root, ttl, type Grant } from './domain.js';
import { YoutubeGrants, attemptContext, connectionContext } from './grants.js';

const live = ['created', 'authorizing', 'exchanging', 'awaiting_confirmation'];
const clean = {
  launchHash: null,
  launchBox: null,
  stateHash: null,
  cookieHash: null,
  nonceHash: null,
  verifierBox: null,
  returnHash: null,
  refreshBox: null,
  subject: null,
  scopes: null,
};
const missing = () => new LinkError(404, 'ATTEMPT_NOT_FOUND');
const stale = () => new LinkError(409, 'STALE_ATTEMPT');
const projection = (a: ExternalMusicLinkAttempt) => ({
  attemptId: a.id,
  status: a.status,
  reason: a.reason,
  expiresAt: a.expiresAt,
  channel: a.channelId ? { id: a.channelId, title: a.channelTitle } : null,
});
export class YoutubeLinkService {
  constructor(
    readonly grants: YoutubeGrants,
    readonly callback: URL,
    readonly appReturn: URL,
    readonly enabled: boolean,
  ) {}
  private allow() {
    if (!this.enabled) throw new LinkError(503, 'LINK_DISABLED');
  }
  async owner(uid: string) {
    const user = await getDatabase().user.findUnique({
      where: { firebaseUid: uid },
      select: { id: true },
    });
    if (!user) throw new LinkError(404, 'PROFILE_NOT_FOUND');
    return user.id;
  }
  private async discard(
    db: YoutubeTx,
    a: ExternalMusicLinkAttempt,
    status: string,
    reason: string | null = null,
  ) {
    await db.externalMusicLinkAttempt.update({
      where: { id: a.id },
      data: { ...clean, status, reason, channelId: null, channelTitle: null },
    });
    if (a.refreshBox && a.subject)
      await this.grants.retire(
        db,
        a.userId,
        a.subject,
        this.grants.box.open(
          a.refreshBox,
          attemptContext(a.id, a.userId, 'refresh'),
        ),
      );
  }
  async start(userId: string, requestKey: string, forceConsent: boolean) {
    this.allow();
    return youtubeWrite(async (db) => {
      let a = await db.externalMusicLinkAttempt.findUnique({
        where: { userId_requestKey: { userId, requestKey } },
      });
      if (a && (a.expiresAt <= new Date() || a.forceConsent !== forceConsent))
        throw stale();
      if (!a) {
        for (const old of await db.externalMusicLinkAttempt.findMany({
          where: { userId, status: { in: live } },
        }))
          await this.discard(db, old, 'canceled');
        const id = randomUUID(),
          ref = randomRef();
        a = await db.externalMusicLinkAttempt.create({
          data: {
            id,
            userId,
            requestKey,
            status: 'created',
            forceConsent,
            expiresAt: new Date(Date.now() + ttl),
            launchHash: digest(ref),
            launchBox: this.grants.box.seal(
              ref,
              attemptContext(id, userId, 'launch'),
            ),
          },
        });
      }
      const url = new URL(root + '/browser/start', this.callback);
      if (a.launchBox)
        url.searchParams.set(
          'ref',
          this.grants.box.open(
            a.launchBox,
            attemptContext(a.id, userId, 'launch'),
          ),
        );
      return {
        attemptId: a.id,
        expiresAt: a.expiresAt,
        status: a.status,
        launchUrl: a.launchBox ? url.href : null,
      };
    });
  }
  async begin(ref: string) {
    this.allow();
    const nonce = randomRef(),
      state = randomRef(),
      cookie = randomRef(),
      verifier = randomRef();
    const consent = await youtubeWrite(async (db) => {
      const a = await db.externalMusicLinkAttempt.findUnique({
        where: { launchHash: digest(ref) },
      });
      if (!a || a.status !== 'created' || a.expiresAt <= new Date())
        throw stale();
      await db.externalMusicLinkAttempt.update({
        where: { id: a.id },
        data: {
          status: 'authorizing',
          launchHash: null,
          launchBox: null,
          stateHash: digest(state),
          cookieHash: digest(cookie),
          nonceHash: digest(nonce),
          verifierBox: this.grants.box.seal(
            verifier,
            attemptContext(a.id, a.userId, 'pkce'),
          ),
        },
      });
      return a.forceConsent;
    });
    return {
      cookie,
      url: this.grants.google.authorize({
        nonce,
        state,
        challenge: digest(verifier),
        consent,
      }),
    };
  }
  async finish(
    state: string,
    cookie: string,
    code?: string,
    providerError?: string,
  ) {
    this.allow();
    const a = await youtubeWrite(async (db) => {
      const attempt = await db.externalMusicLinkAttempt.findUnique({
        where: { stateHash: digest(state) },
      });
      if (
        !attempt ||
        attempt.cookieHash !== digest(cookie) ||
        attempt.status !== 'authorizing' ||
        attempt.expiresAt <= new Date()
      )
        throw stale();
      await db.externalMusicLinkAttempt.update({
        where: { id: attempt.id },
        data: { ...clean, status: 'exchanging' },
      });
      return attempt;
    });
    const ref = randomRef();
    let grant: Grant | undefined,
      channel: { id: string; title: string } | undefined,
      failure: string | undefined;
    try {
      if (providerError || !code)
        throw new LinkError(
          409,
          providerError === 'access_denied'
            ? 'ACCESS_DENIED'
            : 'AUTHORIZATION_FAILED',
        );
      grant = await this.grants.google.exchange(
        code,
        this.grants.box.open(
          a.verifierBox!,
          attemptContext(a.id, a.userId, 'pkce'),
        ),
        a.nonceHash!,
      );
      if (
        !grant.scope?.split(' ').includes(readScope) ||
        !grant.scope.split(' ').includes('openid')
      )
        throw new LinkError(409, 'MISSING_SCOPE');
      if (!grant.refresh) throw new LinkError(409, 'MISSING_REFRESH_TOKEN');
      channel = await this.grants.google.channel(grant.access);
    } catch (e) {
      failure = e instanceof LinkError ? e.code : 'GOOGLE_UNAVAILABLE';
    }
    const revocationId = await youtubeWrite(async (db) => {
      const current = await db.externalMusicLinkAttempt.findUnique({
        where: { id: a.id },
      });
      const claim = current?.status === 'exchanging';
      if (!claim || a.expiresAt <= new Date()) failure = 'EXPIRED';
      if (grant && !failure) {
        const linked = await db.externalMusicConnection.findUnique({
          where: { subject: grant.subject },
        });
        const pending = await db.externalMusicLinkAttempt.findFirst({
          where: { subject: grant.subject, status: 'awaiting_confirmation' },
        });
        const job = await db.externalMusicRevocationJob.findUnique({
          where: { subject: grant.subject },
        });
        if ((linked && linked.userId !== a.userId) || pending || job)
          failure = 'LINK_CONFLICT';
      }
      if (failure || !grant?.refresh || !channel) {
        if (claim)
          await db.externalMusicLinkAttempt.update({
            where: { id: a.id },
            data: {
              status:
                failure === 'ACCESS_DENIED'
                  ? 'denied'
                  : failure === 'EXPIRED'
                    ? 'expired'
                    : 'failed',
              reason: failure ?? 'AUTHORIZATION_FAILED',
            },
          });
        if (grant)
          return this.grants.retire(
            db,
            a.userId,
            grant.subject,
            grant.refresh || grant.access,
          );
        return;
      }
      await db.externalMusicLinkAttempt.update({
        where: { id: a.id },
        data: {
          status: 'awaiting_confirmation',
          returnHash: digest(ref),
          subject: grant.subject,
          scopes: grant.scope,
          channelId: channel.id,
          channelTitle: channel.title,
          refreshBox: this.grants.box.seal(
            grant.refresh,
            attemptContext(a.id, a.userId, 'refresh'),
          ),
        },
      });
    });
    if (revocationId) await this.grants.drain(revocationId);
    const ret = new URL(this.appReturn);
    ret.hash = new URLSearchParams({
      attemptId: a.id,
      ...(!failure ? { returnRef: ref } : {}),
    }).toString();
    return ret.href;
  }
  async attempt(userId: string, id: string) {
    return youtubeWrite(async (db) => {
      const a = await db.externalMusicLinkAttempt.findUnique({
        where: { id, userId },
      });
      if (!a) throw missing();
      if (live.includes(a.status) && a.expiresAt <= new Date()) {
        await this.discard(db, a, 'expired');
        return { ...projection(a), status: 'expired', channel: null };
      }
      return projection(a);
    });
  }
  async confirm(
    userId: string,
    id: string,
    data: { returnRef?: string; channelId?: string; replace?: boolean },
  ) {
    this.allow();
    return youtubeWrite(async (db) => {
      const a = await db.externalMusicLinkAttempt.findUnique({
        where: { id, userId },
      });
      if (!a) throw missing();
      if (a.status === 'confirmed') return projection(a);
      if (
        a.status !== 'awaiting_confirmation' ||
        a.expiresAt <= new Date() ||
        !a.subject ||
        !a.refreshBox ||
        !a.channelId
      )
        throw stale();
      if (data.returnRef && digest(data.returnRef) !== a.returnHash)
        throw stale();
      if (!data.returnRef && !data.channelId)
        throw new LinkError(409, 'CONFIRM_CHANNEL');
      if (data.channelId && data.channelId !== a.channelId)
        throw new LinkError(409, 'CHANNEL_MISMATCH');
      const old = await db.externalMusicConnection.findUnique({
        where: { userId },
      });
      const changed =
        old && (old.subject !== a.subject || old.channelId !== a.channelId);
      if (changed && (!data.replace || data.channelId !== a.channelId))
        throw new LinkError(409, 'CONFIRM_REPLACEMENT');
      if (
        await db.externalMusicRevocationJob.findUnique({
          where: { subject: a.subject },
        })
      )
        throw new LinkError(409, 'LINK_CONFLICT');
      const generation = randomUUID(),
        context = connectionContext({ userId, generation });
      const record = {
        userId,
        subject: a.subject,
        channelId: a.channelId,
        channelTitle: a.channelTitle ?? '',
        status: 'linked',
        generation,
        scopes: a.scopes!,
        refreshBox: this.grants.box.seal(
          this.grants.box.open(
            a.refreshBox,
            attemptContext(id, userId, 'refresh'),
          ),
          context,
        ),
        connectedAt: new Date(),
        checkedAt: new Date(),
        lease: null,
        leaseUntil: null,
      };
      await db.externalMusicConnection.upsert({
        where: { userId },
        create: record,
        update: record,
      });
      if (old) {
        this.grants.forget(old.generation);
        if (old.subject !== a.subject && old.refreshBox)
          await this.grants.retire(
            db,
            userId,
            old.subject,
            this.grants.box.open(old.refreshBox, connectionContext(old)),
            old.leaseUntil,
          );
      }
      await db.externalMusicLinkAttempt.updateMany({
        where: { userId, status: 'confirmed', id: { not: id } },
        data: { status: 'canceled', channelId: null, channelTitle: null },
      });
      return projection(
        await db.externalMusicLinkAttempt.update({
          where: { id },
          data: { ...clean, status: 'confirmed' },
        }),
      );
    });
  }
  async connection(userId: string) {
    const c = await getDatabase().externalMusicConnection.findUnique({
      where: { userId },
      select: {
        status: true,
        channelId: true,
        channelTitle: true,
        connectedAt: true,
        checkedAt: true,
        generation: true,
      },
    });
    if (c)
      return {
        status: c.status,
        channel: { id: c.channelId, title: c.channelTitle },
        generation: c.generation,
        connectedAt: c.connectedAt,
        lastCheckedAt: c.checkedAt,
      };
    const pending = await getDatabase().externalMusicRevocationJob.findFirst({
      where: { ownerId: userId },
      select: { id: true },
    });
    return {
      status: pending ? 'revocation_pending' : 'unlinked',
      channel: null,
    };
  }
  async unlink(userId: string) {
    await youtubeWrite(async (db) => {
      for (const a of await db.externalMusicLinkAttempt.findMany({
        where: { userId, status: { in: live } },
      }))
        await this.discard(db, a, 'canceled');
      await db.externalMusicLinkAttempt.updateMany({
        where: { userId, status: 'confirmed' },
        data: { status: 'canceled', channelId: null, channelTitle: null },
      });
      const c = await db.externalMusicConnection.findUnique({
        where: { userId },
      });
      if (c) {
        await db.externalMusicConnection.delete({ where: { userId } });
        this.grants.forget(c.generation);
        if (c.refreshBox)
          await this.grants.retire(
            db,
            userId,
            c.subject,
            this.grants.box.open(c.refreshBox, connectionContext(c)),
            c.leaseUntil,
          );
      }
    });
    const jobs = await getDatabase().externalMusicRevocationJob.findMany({
      where: { ownerId: userId },
      select: { id: true },
      take: 10,
    });
    await Promise.all(jobs.map((job) => this.grants.drain(job.id)));
    return (
      (await getDatabase().externalMusicRevocationJob.count({
        where: { ownerId: userId },
      })) > 0
    );
  }
  async maintain() {
    const now = new Date(),
      db = getDatabase();
    const expired = await db.externalMusicLinkAttempt.findMany({
      where: { status: { in: live }, expiresAt: { lte: now } },
      select: { id: true, userId: true },
      take: 100,
    });
    for (const a of expired)
      await this.attempt(a.userId, a.id).catch((e) => {
        if (!(e instanceof LinkError && e.status === 404)) throw e;
      });
    await db.externalMusicLinkAttempt.deleteMany({
      where: {
        status: { notIn: live },
        expiresAt: { lt: new Date(Date.now() - 86400_000) },
      },
    });
    const jobs = await db.externalMusicRevocationJob.findMany({
      where: { nextAt: { lte: now } },
      orderBy: { nextAt: 'asc' },
      select: { id: true },
      take: 50,
    });
    let pendingRevokes = 0;
    for (const job of jobs)
      if ((await this.grants.drain(job.id)) === 'pending') pendingRevokes++;
    const staleConnections = await db.externalMusicConnection.findMany({
      where: {
        status: 'linked',
        checkedAt: { lt: new Date(Date.now() - 86400_000) },
      },
      orderBy: { checkedAt: 'asc' },
      select: { userId: true },
      take: 50,
    });
    let refreshFailures = 0;
    for (const c of staleConnections)
      await this.grants.access(c.userId, true).catch((e) => {
        if (!(e instanceof LinkError)) throw e;
        refreshFailures++;
      });
    return {
      expired: expired.length,
      revocationsExamined: jobs.length,
      pendingRevokes,
      connectionsExamined: staleConnections.length,
      refreshFailures,
    };
  }
}
