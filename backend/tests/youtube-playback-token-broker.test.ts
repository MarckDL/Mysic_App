import { EventEmitter } from 'node:events';
import type { ChildProcess } from 'node:child_process';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { YoutubePlaybackTokenBroker } from '../src/infrastructure/music/youtube-playback-token-broker.js';

class FakeWorker extends EventEmitter {
  connected = true;
  killed = false;
  messages: unknown[] = [];

  send(message: unknown, callback?: (error: Error | null) => void) {
    this.messages.push(message);
    callback?.(null);
    return true;
  }

  kill() {
    this.killed = true;
    this.connected = false;
    return true;
  }

  reply(message: unknown) {
    this.emit('message', message);
  }
}

const sourceId = 'abcdefghijk';
const asChild = (worker: FakeWorker) => worker as unknown as ChildProcess;

afterEach(() => vi.useRealTimers());

describe('YoutubePlaybackTokenBroker', () => {
  it('comparte solicitudes concurrentes y reutiliza el lease vigente', async () => {
    const worker = new FakeWorker();
    const broker = new YoutubePlaybackTokenBroker(() => asChild(worker));
    const first = broker.prepare(sourceId);
    const second = broker.prepare(sourceId);
    expect(worker.messages).toEqual([
      { type: 'prepare', requestId: 1, sourceId },
    ]);
    worker.reply({
      type: 'ready',
      requestId: 1,
      sourceId,
      expiresAtMs: Date.now() + 120_000,
    });
    expect(await first).toEqual(await second);
    await broker.prepare(sourceId);
    expect(worker.messages).toHaveLength(1);
    await broker.close();
  });

  it('invalida por video y nunca acepta un token ligado a otro video', async () => {
    const worker = new FakeWorker();
    const broker = new YoutubePlaybackTokenBroker(() => asChild(worker));
    const rejected = broker.prepare(sourceId);
    worker.reply({
      type: 'ready',
      requestId: 1,
      sourceId: 'other000000',
      expiresAtMs: Date.now() + 120_000,
    });
    await expect(rejected).rejects.toThrow();

    const prepared = broker.prepare(sourceId);
    worker.reply({
      type: 'ready',
      requestId: 2,
      sourceId,
      expiresAtMs: Date.now() + 120_000,
    });
    await prepared;
    broker.invalidate(sourceId);
    expect(worker.messages.at(-1)).toEqual({ type: 'invalidate', sourceId });
    const refreshed = broker.prepare(sourceId);
    expect(worker.messages.at(-1)).toEqual({
      type: 'prepare',
      requestId: 3,
      sourceId,
    });
    worker.reply({
      type: 'ready',
      requestId: 3,
      sourceId,
      expiresAtMs: Date.now() + 120_000,
    });
    await refreshed;
    await broker.close();
  });

  it('respeta el aborto de un consumidor sin cancelar a los demás', async () => {
    const worker = new FakeWorker();
    const broker = new YoutubePlaybackTokenBroker(() => asChild(worker));
    const controller = new AbortController();
    const cancelled = broker.prepare(sourceId, controller.signal);
    const active = broker.prepare(sourceId);
    controller.abort();
    await expect(cancelled).rejects.toThrow();
    worker.reply({
      type: 'ready',
      requestId: 1,
      sourceId,
      expiresAtMs: Date.now() + 120_000,
    });
    await expect(active).resolves.toMatchObject({ sourceId });
    await broker.close();
  });

  it('reinicia el worker caído y no deja solicitudes pendientes', async () => {
    const workers = [new FakeWorker(), new FakeWorker()];
    const factory = vi.fn(() =>
      asChild(workers[factory.mock.calls.length - 1]!),
    );
    const broker = new YoutubePlaybackTokenBroker(factory);
    const failed = broker.prepare(sourceId);
    workers[0]!.connected = false;
    workers[0]!.emit('exit', 1);
    await expect(failed).rejects.toThrow();
    const retried = broker.prepare(sourceId);
    workers[1]!.reply({
      type: 'ready',
      requestId: 2,
      sourceId,
      expiresAtMs: Date.now() + 120_000,
    });
    await expect(retried).resolves.toMatchObject({ sourceId });
    expect(factory).toHaveBeenCalledTimes(2);
    await broker.close();
  });

  it('vence la solicitud, mata el worker y rechaza IDs inválidos', async () => {
    vi.useFakeTimers();
    const worker = new FakeWorker();
    const broker = new YoutubePlaybackTokenBroker(() => asChild(worker), 50);
    await expect(broker.prepare('invalid')).rejects.toThrow();
    const result = expect(broker.prepare(sourceId)).rejects.toThrow();
    await vi.advanceTimersByTimeAsync(50);
    await result;
    expect(worker.killed).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
    await broker.close();
  });
});
