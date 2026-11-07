import { spawn, type ChildProcess } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import type {
  PlaybackAttestationLease,
  PlaybackTokenBroker,
} from '../../modules/playback/domain/playback-token-broker.js';
import {
  playbackClients,
  type PlaybackSourceResolver,
  type ResolvedPlaybackSource,
} from '../../modules/playback/domain/playback-source-resolver.js';

type WorkerMessage =
  | { type: 'warmed'; requestId: number }
  | { type: 'ready'; requestId: number; sourceId: string; expiresAtMs: number }
  | {
      type: 'resolved';
      requestId: number;
      sourceId: string;
      client: string;
      itag: number;
      privateUrl: string;
      mimeType: string;
      contentLength: number;
      durationMs: number;
      expiresAtMs: number;
    }
  | { type: 'error'; requestId: number; reason?: string };

type Pending = {
  sourceId: string;
  resolve: (lease: PlaybackAttestationLease) => void;
  reject: (reason?: string) => void;
  timer: ReturnType<typeof setTimeout>;
};

type WorkerFactory = () => ChildProcess;

export type PlaybackMetric = Readonly<{
  stage: 'worker-warm' | 'resolution';
  durationMs: number;
  cacheHit: boolean;
  success: boolean;
  reason?: 'timeout' | 'worker-error' | 'worker-exit';
}>;

function metricReason(error: unknown): PlaybackMetric['reason'] {
  if (!(error instanceof Error)) return 'worker-error';
  if (error.message === 'timeout') return 'timeout';
  if (error.message === 'worker-exit') return 'worker-exit';
  return 'worker-error';
}

function defaultWorkerFactory() {
  const root = fileURLToPath(new URL('../../../', import.meta.url));
  const worker = fileURLToPath(
    new URL('../../../tool/youtube-token-worker.mjs', import.meta.url),
  );
  return spawn(
    process.execPath,
    [
      '--permission',
      '--max-old-space-size=384',
      `--allow-fs-read=${root}node_modules`,
      `--allow-fs-read=${root}package.json`,
      `--allow-fs-read=${worker}`,
      worker,
    ],
    {
      cwd: root,
      env: Object.fromEntries(
        Object.entries(process.env).filter(([key]) =>
          [
            'LANG',
            'HTTPS_PROXY',
            'HTTP_PROXY',
            'ALL_PROXY',
            'NO_PROXY',
            'https_proxy',
            'http_proxy',
            'all_proxy',
            'no_proxy',
            'NODE_USE_ENV_PROXY',
          ].includes(key),
        ),
      ),
      stdio: ['ignore', 'ignore', 'ignore', 'ipc'],
    },
  );
}

export class YoutubePlaybackTokenBroker
  implements PlaybackTokenBroker, PlaybackSourceResolver
{
  private child?: ChildProcess;
  private requestId = 0;
  private readonly pending = new Map<number, Pending>();
  private readonly leases = new Map<string, PlaybackAttestationLease>();
  private readonly inFlight = new Map<
    string,
    Promise<PlaybackAttestationLease>
  >();
  private readonly resolved = new Map<string, ResolvedPlaybackSource>();
  private readonly resolving = new Map<
    string,
    Promise<ResolvedPlaybackSource>
  >();
  private warmRequest?: Promise<void>;
  private warmed = false;
  private readonly warmPending = new Map<
    number,
    {
      resolve: () => void;
      reject: (reason?: string) => void;
      timer: ReturnType<typeof setTimeout>;
    }
  >();

  constructor(
    private readonly workerFactory: WorkerFactory = defaultWorkerFactory,
    // En un hosting recién despertado, crear la sesión, el intérprete y la
    // atestación puede superar 15 s aunque el mismo flujo en caliente tarde 6 s.
    private readonly timeoutMs = 30_000,
    private readonly now: () => number = Date.now,
    private readonly metric: (value: PlaybackMetric) => void = () => {},
  ) {}

  warm(signal?: AbortSignal) {
    if (signal?.aborted)
      return Promise.reject(new Error('Playback worker unavailable'));
    if (this.warmed) return Promise.resolve();
    if (!this.warmRequest) {
      const started = this.now();
      this.warmRequest = this.requestWarm()
        .then(() => {
          this.warmed = true;
          this.metric({
            stage: 'worker-warm',
            durationMs: this.now() - started,
            cacheHit: false,
            success: true,
          });
        })
        .catch((error: unknown) => {
          this.metric({
            stage: 'worker-warm',
            durationMs: this.now() - started,
            cacheHit: false,
            success: false,
            reason: metricReason(error),
          });
          throw error;
        })
        .finally(() => {
          this.warmRequest = undefined;
        });
    }
    return this.observeVoid(this.warmRequest, signal);
  }

  prepare(sourceId: string, signal?: AbortSignal) {
    if (!/^[A-Za-z0-9_-]{11}$/.test(sourceId) || signal?.aborted)
      return Promise.reject(new Error('Playback attestation unavailable'));
    const cached = this.leases.get(sourceId);
    if (cached && cached.expiresAtMs > this.now() + 30_000)
      return Promise.resolve(cached);
    const current = this.inFlight.get(sourceId);
    if (current) return this.observe(current, signal);
    const request = this.request(sourceId).finally(() => {
      if (this.inFlight.get(sourceId) === request)
        this.inFlight.delete(sourceId);
    });
    this.inFlight.set(sourceId, request);
    return this.observe(request, signal);
  }

  invalidate(sourceId: string) {
    this.leases.delete(sourceId);
    this.resolved.delete(sourceId);
    if (this.child?.connected)
      this.child.send({ type: 'invalidate', sourceId }, () => {});
  }

  async close() {
    const child = this.child;
    this.child = undefined;
    this.leases.clear();
    this.resolved.clear();
    this.warmed = false;
    this.rejectAll();
    if (!child) return;
    child.send?.({ type: 'shutdown' }, () => {});
    if (!child.killed) child.kill('SIGTERM');
  }

  resolve(sourceId: string, signal?: AbortSignal) {
    if (!/^[A-Za-z0-9_-]{11}$/.test(sourceId) || signal?.aborted)
      return Promise.reject(new Error('Playback source unavailable'));
    const cached = this.resolved.get(sourceId);
    if (cached && cached.expiresAtMs > this.now() + 30_000) {
      this.metric({
        stage: 'resolution',
        durationMs: 0,
        cacheHit: true,
        success: true,
      });
      return Promise.resolve(cached);
    }
    const current = this.resolving.get(sourceId);
    if (current) return this.observeResolution(current, signal);
    const started = this.now();
    const request = this.requestResolution(sourceId)
      .then((value) => {
        this.metric({
          stage: 'resolution',
          durationMs: this.now() - started,
          cacheHit: false,
          success: true,
        });
        return value;
      })
      .catch((error: unknown) => {
        this.metric({
          stage: 'resolution',
          durationMs: this.now() - started,
          cacheHit: false,
          success: false,
          reason: metricReason(error),
        });
        throw error;
      })
      .finally(() => {
        if (this.resolving.get(sourceId) === request)
          this.resolving.delete(sourceId);
      });
    this.resolving.set(sourceId, request);
    return this.observeResolution(request, signal);
  }

  private request(sourceId: string) {
    const child = this.getWorker();
    const requestId = ++this.requestId;
    return new Promise<PlaybackAttestationLease>((resolve, reject) => {
      const fail = (reason = 'worker-error') => reject(new Error(reason));
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        fail('timeout');
        this.restartWorker(child);
      }, this.timeoutMs);
      this.pending.set(requestId, {
        sourceId,
        resolve: (lease) => {
          resolve(lease);
        },
        reject: fail,
        timer,
      });
      child.send({ type: 'prepare', requestId, sourceId }, (error) => {
        if (!error) return;
        clearTimeout(timer);
        this.pending.delete(requestId);
        fail();
      });
    });
  }

  private requestWarm() {
    const child = this.getWorker();
    const requestId = ++this.requestId;
    return new Promise<void>((resolve, reject) => {
      const fail = (reason = 'worker-error') => reject(new Error(reason));
      const timer = setTimeout(() => {
        this.warmPending.delete(requestId);
        fail('timeout');
        this.restartWorker(child);
      }, this.timeoutMs);
      this.warmPending.set(requestId, { resolve, reject: fail, timer });
      child.send({ type: 'warm', requestId }, (error) => {
        if (!error) return;
        clearTimeout(timer);
        this.warmPending.delete(requestId);
        fail();
      });
    });
  }

  private requestResolution(sourceId: string) {
    const child = this.getWorker();
    const requestId = ++this.requestId;
    return new Promise<ResolvedPlaybackSource>((resolve, reject) => {
      const fail = (reason = 'worker-error') => reject(new Error(reason));
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        fail('timeout');
        this.restartWorker(child);
      }, this.timeoutMs);
      this.pending.set(requestId, {
        sourceId,
        resolve: (value) => resolve(value as unknown as ResolvedPlaybackSource),
        reject: fail,
        timer,
      });
      child.send({ type: 'resolve', requestId, sourceId }, (error) => {
        if (!error) return;
        clearTimeout(timer);
        this.pending.delete(requestId);
        fail();
      });
    });
  }

  private getWorker() {
    if (this.child?.connected) return this.child;
    const child = this.workerFactory();
    this.child = child;
    child.on('message', (value: unknown) => this.handleMessage(value));
    child.once('error', () => this.restartWorker(child));
    child.once('exit', () => this.restartWorker(child));
    return child;
  }

  private handleMessage(value: unknown) {
    if (!value || typeof value !== 'object' || !('type' in value)) return;
    const message = value as WorkerMessage;
    if (!Number.isSafeInteger(message.requestId)) return;
    const safeReason =
      message.type === 'error' && message.reason === 'timeout'
        ? 'timeout'
        : 'worker-error';
    if (message.type === 'warmed') {
      const warm = this.warmPending.get(message.requestId);
      if (!warm) return;
      clearTimeout(warm.timer);
      this.warmPending.delete(message.requestId);
      warm.resolve();
      return;
    }
    if (message.type === 'error') {
      const warm = this.warmPending.get(message.requestId);
      if (warm) {
        clearTimeout(warm.timer);
        this.warmPending.delete(message.requestId);
        warm.reject(safeReason);
        return;
      }
    }
    const pending = this.pending.get(message.requestId);
    if (!pending) return;
    clearTimeout(pending.timer);
    this.pending.delete(message.requestId);
    if (message.type === 'resolved') {
      if (!this.validResolution(message, pending.sourceId)) {
        pending.reject();
        return;
      }
      const resolution: ResolvedPlaybackSource = {
        sourceId: message.sourceId,
        client: message.client as ResolvedPlaybackSource['client'],
        itag: message.itag,
        privateUrl: message.privateUrl,
        mimeType: message.mimeType,
        contentLength: message.contentLength,
        durationMs: message.durationMs,
        expiresAtMs: message.expiresAtMs,
      };
      this.resolved.set(message.sourceId, resolution);
      pending.resolve(resolution as unknown as PlaybackAttestationLease);
      return;
    }
    if (
      message.type !== 'ready' ||
      message.sourceId !== pending.sourceId ||
      !/^[A-Za-z0-9_-]{11}$/.test(message.sourceId) ||
      !Number.isSafeInteger(message.expiresAtMs) ||
      message.expiresAtMs <= this.now()
    ) {
      pending.reject(message.type === 'error' ? safeReason : 'worker-error');
      return;
    }
    const lease = {
      sourceId: message.sourceId,
      expiresAtMs: message.expiresAtMs,
    };
    this.leases.set(message.sourceId, lease);
    pending.resolve(lease);
  }

  private validResolution(
    message: Extract<WorkerMessage, { type: 'resolved' }>,
    expectedSourceId: string,
  ) {
    if (
      message.sourceId !== expectedSourceId ||
      !playbackClients.includes(
        message.client as (typeof playbackClients)[number],
      ) ||
      !Number.isSafeInteger(message.itag) ||
      message.itag <= 0 ||
      !/^audio\/(?:mp4|webm)(?:; codecs="[A-Za-z0-9., _-]+")?$/.test(
        message.mimeType,
      ) ||
      !Number.isSafeInteger(message.contentLength) ||
      message.contentLength <= 0 ||
      !Number.isFinite(message.durationMs) ||
      message.durationMs <= 0 ||
      !Number.isSafeInteger(message.expiresAtMs) ||
      message.expiresAtMs <= this.now()
    )
      return false;
    try {
      const url = new URL(message.privateUrl);
      return (
        url.protocol === 'https:' &&
        !url.username &&
        !url.password &&
        url.hostname.endsWith('.googlevideo.com')
      );
    } catch {
      return false;
    }
  }

  private restartWorker(child: ChildProcess) {
    if (this.child !== child) return;
    this.child = undefined;
    this.warmed = false;
    if (!child.killed) child.kill('SIGKILL');
    this.rejectAll('worker-exit');
  }

  private rejectAll(reason = 'worker-error') {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(reason);
    }
    this.pending.clear();
    for (const pending of this.warmPending.values()) {
      clearTimeout(pending.timer);
      pending.reject(reason);
    }
    this.warmPending.clear();
  }

  private observe(
    request: Promise<PlaybackAttestationLease>,
    signal?: AbortSignal,
  ) {
    if (!signal) return request;
    return new Promise<PlaybackAttestationLease>((resolve, reject) => {
      const abort = () => reject(new Error('Playback attestation unavailable'));
      signal.addEventListener('abort', abort, { once: true });
      void request.then(
        (lease) => {
          signal.removeEventListener('abort', abort);
          resolve(lease);
        },
        (error: unknown) => {
          signal.removeEventListener('abort', abort);
          reject(error);
        },
      );
    });
  }

  private observeResolution(
    request: Promise<ResolvedPlaybackSource>,
    signal?: AbortSignal,
  ) {
    if (!signal) return request;
    return new Promise<ResolvedPlaybackSource>((resolve, reject) => {
      const abort = () => reject(new Error('Playback source unavailable'));
      signal.addEventListener('abort', abort, { once: true });
      void request.then(
        (source) => {
          signal.removeEventListener('abort', abort);
          resolve(source);
        },
        (error: unknown) => {
          signal.removeEventListener('abort', abort);
          reject(error);
        },
      );
    });
  }

  private observeVoid(request: Promise<void>, signal?: AbortSignal) {
    if (!signal) return request;
    return new Promise<void>((resolve, reject) => {
      const abort = () => reject(new Error('Playback worker unavailable'));
      signal.addEventListener('abort', abort, { once: true });
      void request.then(
        () => {
          signal.removeEventListener('abort', abort);
          resolve();
        },
        (error: unknown) => {
          signal.removeEventListener('abort', abort);
          reject(error);
        },
      );
    });
  }
}
