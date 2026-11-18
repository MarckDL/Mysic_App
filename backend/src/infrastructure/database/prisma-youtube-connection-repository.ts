import { getDatabase } from './prisma.js';
import type { Prisma } from '../../generated/prisma/client.js';

export type YoutubeTx = Prisma.TransactionClient;
// Serialize short state transitions, including subject reservations across users.
// Remote OAuth calls always run outside this transaction.
export const youtubeWrite = <T>(work: (db: YoutubeTx) => Promise<T>) =>
  getDatabase().$transaction(async (db) => {
    await db.$executeRaw`SELECT pg_advisory_xact_lock(231907, 1)`;
    return work(db);
  });
