import { randomUUID } from 'node:crypto';
import { getDatabase } from '../../../infrastructure/database/prisma.js';
import {
  youtubeWrite,
  type YoutubeTx,
} from '../../../infrastructure/database/prisma-youtube-connection-repository.js';
import { SecretBox } from '../../../infrastructure/youtube/secrets.js';
import { LinkError, readScope, type GoogleOAuthClient } from './domain.js';
import type { ExternalMusicConnection } from '../../../generated/prisma/client.js';

export const attemptContext = (id: string, user: string, purpose: string) =>
  `youtube:attempt:${user}:${id}:${purpose}`;
export const connectionContext = (row: {
  userId: string;
  generation: string;
}) => `youtube:connection:${row.userId}:${row.generation}`;
const jobContext = (id: string, owner: string) =>
  `youtube:revocation:${owner}:${id}`;
export class YoutubeGrants {
  private readonly cache = new Map<string, { access: string; until: number }>();
  private readonly flights = new Map<string, Promise<string>>();
  constructor(
    readonly box: SecretBox,
    readonly google: GoogleOAuthClient,
  ) {}

  // Call after removing the retiring attempt/connection inside the same transaction.
  async retire(
    db: YoutubeTx,
    ownerId: string,
    subject: string,
    token: string,
    after?: Date | null,
  ) {
    if (
      await db.externalMusicConnection.findUnique({
        where: { subject, status: 'linked' },
      })
    )
      return;
    if (
      await db.externalMusicLinkAttempt.findFirst({
        where: { subject, status: 'awaiting_confirmation' },
      })
    )
      return;
    const id = randomUUID();
    const job = await db.externalMusicRevocationJob.upsert({
      where: { subject },
      create: {
        id,
        subject,
        ownerId,
        nextAt: after ?? new Date(),
        refreshBox: this.box.seal(token, jobContext(id, ownerId)),
      },
      update: {},
      select: { id: true },
    });
    return job.id;
  }

  async drain(id: string) {
    const lease = await youtubeWrite(async (db) => {
      const job = await db.externalMusicRevocationJob.findUnique({
        where: { id },
      });
      if (!job || job.nextAt > new Date()) return null;
      return db.externalMusicRevocationJob.update({
        where: { id },
        data: {
          tries: { increment: 1 },
          nextAt: new Date(Date.now() + 60_000),
        },
      });
    });
    if (!lease) return 'skipped';
    try {
      await this.google.revoke(
        this.box.open(lease.refreshBox, jobContext(id, lease.ownerId)),
      );
    } catch {
      if (Date.now() - lease.createdAt.getTime() >= 7 * 86400_000) {
        const purged =
          await getDatabase().externalMusicRevocationJob.deleteMany({
            where: { id, tries: lease.tries },
          });
        if (purged.count)
          console.error(
            JSON.stringify({
              event: 'youtube_revocation_unconfirmed_after_retention',
            }),
          );
        return 'expired';
      }
      await getDatabase().externalMusicRevocationJob.updateMany({
        where: { id, tries: lease.tries },
        data: {
          nextAt: new Date(
            Date.now() + Math.min(3600, 2 ** Math.min(lease.tries, 12)) * 1000,
          ),
        },
      });
      return 'pending';
    }
    await getDatabase().externalMusicRevocationJob.deleteMany({
      where: { id, tries: lease.tries },
    });
    return 'revoked';
  }

  async access(userId: string, force = false, expectedGeneration?: string) {
    const row = await getDatabase().externalMusicConnection.findUnique({
      where: { userId },
    });
    if (!row || row.status !== 'linked')
      throw new LinkError(409, 'REAUTHORIZE_YOUTUBE');
    if (expectedGeneration && row.generation !== expectedGeneration)
      throw new LinkError(409, 'YOUTUBE_LINK_CHANGED');
    const cached = this.cache.get(row.generation);
    if (!force && cached && cached.until > Date.now() + 60_000)
      return cached.access;
    let flight = this.flights.get(row.generation);
    if (!flight) {
      flight = this.refresh(row).finally(() =>
        this.flights.delete(row.generation),
      );
      this.flights.set(row.generation, flight);
    }
    return flight;
  }
  private async refresh(row: ExternalMusicConnection) {
    const lease = randomUUID();
    const result = await getDatabase().externalMusicConnection.updateMany({
      where: {
        generation: row.generation,
        status: 'linked',
        OR: [{ lease: null }, { leaseUntil: { lt: new Date() } }],
      },
      data: { lease, leaseUntil: new Date(Date.now() + 30_000) },
    });
    if (!result.count) throw new LinkError(503, 'REFRESH_BUSY');
    const where = { generation: row.generation, lease, status: 'linked' };
    let rotated: string | undefined;
    try {
      const fresh = await getDatabase().externalMusicConnection.findFirst({
        where,
      });
      if (!fresh?.refreshBox) throw new LinkError(409, 'REAUTHORIZE_YOUTUBE');
      const token = await this.google.refresh(
        this.box.open(fresh.refreshBox, connectionContext(row)),
      );
      rotated = token.refresh;
      if (token.scope && !token.scope.split(' ').includes(readScope))
        throw new LinkError(409, 'MISSING_SCOPE');
      const changed = await getDatabase().externalMusicConnection.updateMany({
        where,
        data: {
          lease: null,
          leaseUntil: null,
          checkedAt: new Date(),
          ...(token.refresh
            ? {
                refreshBox: this.box.seal(
                  token.refresh,
                  connectionContext(row),
                ),
              }
            : {}),
          ...(token.scope ? { scopes: token.scope } : {}),
        },
      });
      if (!changed.count) {
        // Unlink may have queued the former token while Google rotated it.
        await youtubeWrite(async (db) => {
          const job = await db.externalMusicRevocationJob.findUnique({
            where: { subject: row.subject },
          });
          if (job && job.ownerId === row.userId) {
            await db.externalMusicRevocationJob.update({
              where: { id: job.id },
              data: {
                ...(token.refresh
                  ? {
                      refreshBox: this.box.seal(
                        token.refresh,
                        jobContext(job.id, job.ownerId),
                      ),
                    }
                  : {}),
                nextAt: new Date(),
                tries: { increment: 1 },
              },
            });
          }
        });
        throw new LinkError(409, 'REAUTHORIZE_YOUTUBE');
      }
      this.cache.delete(row.generation);
      if (this.cache.size >= 256)
        this.cache.delete(this.cache.keys().next().value!);
      this.cache.set(row.generation, {
        access: token.access,
        until: Date.now() + 1000 * token.expiresIn,
      });
      return token.access;
    } catch (e) {
      const invalid =
        e instanceof LinkError &&
        ['INVALID_GRANT', 'MISSING_SCOPE'].includes(e.code);
      if (invalid) {
        this.cache.delete(row.generation);
        await youtubeWrite(async (db) => {
          const current = await db.externalMusicConnection.findFirst({ where });
          if (!current) return;
          await db.externalMusicConnection.update({
            where: { userId: row.userId },
            data: {
              lease: null,
              leaseUntil: null,
              status: 'reauthorization_required',
              generation: randomUUID(),
              refreshBox: null,
              checkedAt: new Date(),
            },
          });
          if (e.code === 'MISSING_SCOPE' && current.refreshBox)
            await this.retire(
              db,
              row.userId,
              row.subject,
              rotated ??
                this.box.open(current.refreshBox, connectionContext(current)),
            );
        });
        throw new LinkError(409, 'REAUTHORIZE_YOUTUBE');
      }
      await getDatabase().externalMusicConnection.updateMany({
        where,
        data: { lease: null, leaseUntil: null },
      });
      throw e;
    }
  }
  forget(generation: string) {
    this.cache.delete(generation);
  }
}
