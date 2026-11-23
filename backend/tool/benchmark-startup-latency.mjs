/* global process, Response, AbortSignal, Buffer, console */
import express from 'express';
import http from 'node:http';
import { createRequire } from 'node:module';
import { setTimeout as delay } from 'node:timers/promises';
import { createFirebaseTokenVerifier } from '../src/infrastructure/firebase/firebase-token-verifier.ts';
import { OAuthMusicCatalog } from '../src/infrastructure/youtube/music-account-catalog.ts';
import { requireAuth } from '../src/middleware/auth.middleware.ts';
import { createBootstrapRouter } from '../src/modules/bootstrap/presentation/bootstrap.routes.ts';
import { createStreamHeadHandler } from '../../../Backend/src/stream-head-route.mjs';

const require = createRequire(import.meta.url);
const {
  createResponseCache,
} = require('../../../Backend/src/response-cache.js');
const samples = 5;
const spacingMs = 250;

const identity = {
  uid: 'firebase-a',
  firebase: { sign_in_provider: 'google.com' },
};
const slowVerifier = (ttlMs) =>
  createFirebaseTokenVerifier(
    async () => ({
      verifyIdToken: async () => {
        await delay(60);
        return identity;
      },
    }),
    { ttlMs },
  );

function timedRequest(url, options = {}) {
  return new Promise((resolve, reject) => {
    const start = process.hrtime.bigint();
    const request = http.request(url, options, (response) => {
      const headers = process.hrtime.bigint();
      let bytes = 0;
      response.on('data', (chunk) => (bytes += chunk.length));
      response.on('end', () => {
        const end = process.hrtime.bigint();
        resolve({
          status: response.statusCode,
          headersMs: Number(headers - start) / 1e6,
          totalMs: Number(end - start) / 1e6,
          bytes,
        });
      });
    });
    request.on('error', reject);
    request.end();
  });
}

async function listen(app) {
  const server = await new Promise((resolve) => {
    const value = app.listen(0, '127.0.0.1', () => resolve(value));
  });
  return {
    server,
    base: `http://127.0.0.1:${server.address().port}`,
  };
}

async function collect(run) {
  const values = [];
  for (let index = 0; index < samples; index += 1) {
    values.push(await run(index));
    if (index + 1 < samples) await delay(spacingMs);
  }
  return values;
}

async function authCase() {
  const app = express();
  const route = (verifier) => [
    requireAuth(verifier),
    (_req, res) => res.json({ ok: true }),
  ];
  app.get('/before', ...route(slowVerifier(1)));
  app.get('/after', ...route(slowVerifier(90_000)));
  const { server, base } = await listen(app);
  try {
    const headers = { Authorization: 'Bearer token' };
    return {
      before: await collect(() => timedRequest(`${base}/before`, { headers })),
      after: await collect(() => timedRequest(`${base}/after`, { headers })),
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

const rawHome = {
  responseContext: { mainAppWebResponseContext: { loggedOut: false } },
  contents: {
    musicShelfRenderer: {
      contents: [
        {
          musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: 'abcdefghijk' },
            flexColumns: [
              {
                musicResponsiveListItemFlexColumnRenderer: {
                  text: {
                    runs: [
                      {
                        text: 'Canción',
                        navigationEndpoint: {
                          watchEndpoint: {
                            videoId: 'abcdefghijk',
                            watchEndpointMusicSupportedConfigs: {
                              watchEndpointMusicConfig: {
                                musicVideoType: 'MUSIC_VIDEO_TYPE_ATV',
                              },
                            },
                          },
                        },
                      },
                    ],
                  },
                },
              },
            ],
          },
        },
      ],
    },
  },
};

async function homeCase() {
  const app = express();
  const handler = (reuse) => async (_req, res) => {
    const transport = async () => {
      await delay(60);
      return Response.json(rawHome);
    };
    const catalog = new OAuthMusicCatalog(transport);
    const context = { access: 'account', signal: AbortSignal.timeout(2_000) };
    await catalog.verify(context, 'verify-key');
    const home = await catalog.read(
      context,
      { surface: 'home' },
      undefined,
      reuse ? 'verify-key' : 'different-key',
    );
    res.json(home);
  };
  app.get('/before', handler(false));
  app.get('/after', handler(true));
  const { server, base } = await listen(app);
  try {
    return {
      before: await collect(() => timedRequest(`${base}/before`)),
      after: await collect(() => timedRequest(`${base}/after`)),
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function bootstrapCase() {
  const app = express();
  const verifier = {
    verify: async () => {
      await delay(60);
      return { firebaseUid: 'firebase-a', provider: 'google.com' };
    },
  };
  const users = {
    sync: async () => {
      await delay(15);
      return { id: 'user-a', displayName: 'Mysic' };
    },
  };
  const link = { rememberOwner() {} };
  const music = {
    connection: async () => {
      await delay(20);
      return {
        status: 'linked',
        generation: '11111111-1111-4111-8111-111111111111',
      };
    },
    read: async () => {
      await delay(70);
      return {
        items: [{ id: 'abcdefghijk' }],
        nextCursor: null,
        excludedCount: 0,
      };
    },
  };
  app.post('/legacy/sync', requireAuth(verifier), async (_req, res) =>
    res.json(await users.sync()),
  );
  app.get('/legacy/connection', requireAuth(verifier), async (_req, res) =>
    res.json(await music.connection()),
  );
  app.get('/legacy/home', requireAuth(verifier), async (_req, res) =>
    res.json(await music.read()),
  );
  app.use('/bootstrap', createBootstrapRouter(verifier, users, link, music));
  const { server, base } = await listen(app);
  const headers = { Authorization: 'Bearer token' };
  const legacy = async () => {
    const start = process.hrtime.bigint();
    let bytes = 0;
    for (const [method, path] of [
      ['POST', '/legacy/sync'],
      ['GET', '/legacy/connection'],
      ['GET', '/legacy/home'],
    ]) {
      const result = await timedRequest(`${base}${path}`, { method, headers });
      bytes += result.bytes;
    }
    const totalMs = Number(process.hrtime.bigint() - start) / 1e6;
    return { status: 200, headersMs: totalMs, totalMs, bytes };
  };
  try {
    return {
      before: await collect(legacy),
      after: await collect(() =>
        timedRequest(`${base}/bootstrap`, { headers }),
      ),
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function radioCase() {
  const app = express();
  const cache = createResponseCache({ ttlMs: 7 * 60_000 });
  app.use((req, _res, next) => {
    req.mysicUser = { _id: 'user-a' };
    next();
  });
  const load = async (_req, res) => {
    await delay(100);
    res.json({ items: [1, 2, 3] });
  };
  app.get('/before/radio/abcdefghijk', load);
  app.get('/after/radio/abcdefghijk', cache.middleware, load);
  const { server, base } = await listen(app);
  try {
    return {
      before: await collect(() =>
        timedRequest(`${base}/before/radio/abcdefghijk`),
      ),
      after: await collect(() =>
        timedRequest(`${base}/after/radio/abcdefghijk`),
      ),
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function streamCase() {
  const app = express();
  const heads = new Map();
  app.use((req, _res, next) => {
    req.mysicUser = { _id: 'user-a' };
    next();
  });
  app.get('/before/stream/:id', async (_req, res) => {
    await delay(100);
    res.status(206).end(Buffer.alloc(256 * 1024));
  });
  app.get(
    '/after/stream/:id',
    createStreamHeadHandler({
      ready: () => true,
      requestYoutube: async () => ({}),
      resolve: async () => ({
        url: 'https://audio.test/file',
        mimeType: 'audio/webm',
      }),
      peek: (id, scope) => heads.get(`${scope}:${id}`) ?? null,
      prefetch: async (id, _stream, { cacheScope }) => {
        await delay(100);
        const head = {
          body: Buffer.alloc(256 * 1024),
          total: 1024 * 1024,
          contentType: 'audio/webm',
        };
        heads.set(`${cacheScope}:${id}`, head);
        return head;
      },
    }),
  );
  const { server, base } = await listen(app);
  const options = { headers: { Range: 'bytes=0-' } };
  try {
    return {
      before: await collect(() =>
        timedRequest(`${base}/before/stream/abcdefghijk`, options),
      ),
      after: await collect(() =>
        timedRequest(`${base}/after/stream/abcdefghijk`, options),
      ),
    };
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

console.log(
  JSON.stringify(
    {
      metadata: { samples, spacingMs, environment: 'local-controlled' },
      authSession: await authCase(),
      homeVerifyAndRead: await homeCase(),
      startupAggregate: await bootstrapCase(),
      radio: await radioCase(),
      streamHead: await streamCase(),
    },
    null,
    2,
  ),
);
