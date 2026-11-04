import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import type { Readable } from 'node:stream';

export interface AudioStreamTransport {
  open(sourceId: string, signal: AbortSignal): Promise<Readable>;
}

export class YoutubeAudioStream implements AudioStreamTransport {
  async open(sourceId: string, signal: AbortSignal): Promise<Readable> {
    if (!/^[A-Za-z0-9_-]{11}$/.test(sourceId) || signal.aborted)
      throw new Error();
    const root = fileURLToPath(new URL('../../../', import.meta.url));
    const worker = fileURLToPath(
      new URL('../../../tool/youtube-stream-worker.mjs', import.meta.url),
    );
    const child = spawn(
      process.execPath,
      [
        '--permission',
        '--max-old-space-size=384',
        `--allow-fs-read=${root}node_modules`,
        `--allow-fs-read=${root}package.json`,
        `--allow-fs-read=${worker}`,
        worker,
        sourceId,
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
        stdio: ['ignore', 'pipe', 'ignore', 'ipc'],
      },
    );
    const output = child.stdout!;
    return new Promise((resolve, reject) => {
      let ready = false;
      const stop = () => {
        child.kill('SIGKILL');
      };
      const timer = setTimeout(() => {
        reject(new Error());
        stop();
      }, 30_000);
      signal.addEventListener('abort', stop, { once: true });
      child.once('error', () => {
        signal.removeEventListener('abort', stop);
        clearTimeout(timer);
        reject(new Error());
      });
      child.on('message', (message: unknown) => {
        if (!message || typeof message !== 'object' || !('type' in message))
          return;
        if (message.type === 'ready' && !ready && !signal.aborted) {
          ready = true;
          clearTimeout(timer);
          resolve(output);
        } else if (message.type === 'error') {
          reject(new Error());
          if (ready) output.destroy(new Error('Audio unavailable'));
          stop();
        }
      });
      child.once('exit', (code) => {
        clearTimeout(timer);
        signal.removeEventListener('abort', stop);
        if (!ready) reject(new Error());
        else if (code !== 0 && !signal.aborted)
          output.destroy(new Error('Audio interrupted'));
      });
      if (signal.aborted) stop();
    });
  }
}
