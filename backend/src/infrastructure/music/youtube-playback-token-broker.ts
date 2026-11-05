import { spawn, type ChildProcess } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import type {
  PlaybackAttestationLease,
  PlaybackTokenBroker,
} from '../../modules/playback/domain/playback-token-broker.js';

type WorkerMessage =
  | { type: 'ready'; requestId: number; sourceId: string; expiresAtMs: number }
  | { type: 'error'; requestId: number };

type Pending = {
  sourceId: string;
  resolve: (lease: PlaybackAttestationLease) => void;
  reject: () => void;
  timer: ReturnType<typeof setTimeout>;
};

type WorkerFactory = () => ChildProcess;

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

export class YoutubePlaybackTokenBroker implements PlaybackTokenBroker {
  private child?: ChildProcess;
  private requestId = 0;
  private readonly pending = new Map<number, Pending>();
  private readonly leases = new Map<string, PlaybackAttestationLease>();
  private readonly inFlight = new Map<
    string,
    Promise<PlaybackAttestationLease>
  >();

  constructor(
    private readonly workerFactory: WorkerFactory = defaultWorkerFactory,
    private readonly timeoutMs = 15_000,
    private readonly now: () => number = Date.now,
  ) {}

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
    if (this.child?.connected)
      this.child.send({ type: 'invalidate', sourceId }, () => {});
  }

  async close() {
    const child = this.child;
    this.child = undefined;
    this.leases.clear();
    this.rejectAll();
    if (!child) return;
    child.send?.({ type: 'shutdown' }, () => {});
    if (!child.killed) child.kill('SIGTERM');
  }

  private request(sourceId: string) {
    const child = this.getWorker();
    const requestId = ++this.requestId;
    return new Promise<PlaybackAttestationLease>((resolve, reject) => {
      const fail = () => reject(new Error('Playback attestation unavailable'));
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        fail();
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
    const pending = this.pending.get(message.requestId);
    if (!pending) return;
    clearTimeout(pending.timer);
    this.pending.delete(message.requestId);
    if (
      message.type !== 'ready' ||
      message.sourceId !== pending.sourceId ||
      !/^[A-Za-z0-9_-]{11}$/.test(message.sourceId) ||
      !Number.isSafeInteger(message.expiresAtMs) ||
      message.expiresAtMs <= this.now()
    ) {
      pending.reject();
      return;
    }
    const lease = {
      sourceId: message.sourceId,
      expiresAtMs: message.expiresAtMs,
    };
    this.leases.set(message.sourceId, lease);
    pending.resolve(lease);
  }

  private restartWorker(child: ChildProcess) {
    if (this.child !== child) return;
    this.child = undefined;
    if (!child.killed) child.kill('SIGKILL');
    this.rejectAll();
  }

  private rejectAll() {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject();
    }
    this.pending.clear();
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
}
