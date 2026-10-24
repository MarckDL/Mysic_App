import { createApp } from './app.js';
import { readPort } from './config/env.js';

const port = readPort();
const server = createApp().listen(port, () => {
  console.info(JSON.stringify({ event: 'server_started', port }));
});
server.on('error', () => {
  console.error(JSON.stringify({ event: 'server_start_failed' }));
  process.exitCode = 1;
});

for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.once(signal, () => {
    const timeout = setTimeout(() => process.exit(1), 10_000);
    timeout.unref();
    server.close((error) => {
      clearTimeout(timeout);
      process.exit(error ? 1 : 0);
    });
  });
}
