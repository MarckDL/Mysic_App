import { youtubeConfig } from './secrets.js';
import { OfficialGoogleOAuth } from './google-client.js';
import { YoutubeLinkService } from '../../modules/integrations/youtube/link-service.js';
import { YoutubeGrants } from '../../modules/integrations/youtube/grants.js';
export function createYoutubeService() {
  const config = youtubeConfig();
  return config
    ? new YoutubeLinkService(
        new YoutubeGrants(config.box, new OfficialGoogleOAuth(config)),
        config.callback,
        config.appReturn,
        config.enabled,
      )
    : null;
}
