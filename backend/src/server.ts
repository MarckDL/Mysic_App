import { createApp } from './app.js';
import { disconnectDatabase } from './infrastructure/database/prisma.js';
import { readPort } from './config/env.js';
import { YoutubePlaybackTokenBroker } from './infrastructure/music/youtube-playback-token-broker.js';
import { YoutubeAudioStream } from './infrastructure/music/youtube-audio-stream.js';

const port = readPort();
const metric = (value: object) =>
  console.info(JSON.stringify({ event: 'playback_metric', ...value }));
const resolver = new YoutubePlaybackTokenBroker(
  undefined,
  undefined,
  undefined,
  metric,
);
const transport = new YoutubeAudioStream(resolver, fetch, metric);
const server = createApp({ audioStreamTransport: transport }).listen(
  port,
  '0.0.0.0',
  () => {
    console.info(JSON.stringify({ event: 'server_started', port }));
    void transport.warm().catch(() => {});
  },
);
server.on('error', () => {
  console.error(JSON.stringify({ event: 'server_start_failed' }));
  process.exitCode = 1;
});

for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.once(signal, () => {
    const timeout = setTimeout(() => process.exit(1), 10_000);
    timeout.unref();
    server.close((error) => {
      void Promise.all([disconnectDatabase(), transport.close()]).then(
        () => {
          clearTimeout(timeout);
          process.exit(error ? 1 : 0);
        },
        () => {
          clearTimeout(timeout);
          process.exit(1);
        },
      );
    });
  });
}
