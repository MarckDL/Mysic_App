import { disconnectDatabase } from '../infrastructure/database/prisma.js';
import { createYoutubeService } from '../infrastructure/youtube/service.js';
try {
  const service = createYoutubeService();
  if (!service) throw new Error();
  console.info(
    JSON.stringify({
      event: 'youtube_maintenance',
      ...(await service.maintain()),
    }),
  );
} catch {
  console.error(JSON.stringify({ event: 'youtube_maintenance_failed' }));
  process.exitCode = 1;
} finally {
  await disconnectDatabase();
}
