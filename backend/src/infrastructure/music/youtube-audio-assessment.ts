import { ProviderUnavailableError } from '../../modules/catalog/domain/music-provider.js';
import { youtubeSourceIdPattern } from './youtube-normalizer.js';

function object(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

// Solo diagnóstico de capacidades. Nunca devuelve URLs firmadas ni afirma escucha.
export function assessYoutubeAudio(value: unknown, requestedId: string) {
  const info = object(value);
  const basic = object(info.basic_info);
  if (!youtubeSourceIdPattern.test(requestedId) || basic.id !== requestedId) {
    throw new ProviderUnavailableError();
  }
  const streaming = object(info.streaming_data);
  const formats = [
    ...(Array.isArray(streaming.formats) ? streaming.formats : []),
    ...(Array.isArray(streaming.adaptive_formats)
      ? streaming.adaptive_formats
      : []),
  ]
    .map(object)
    .filter((item) => item.has_audio === true && item.has_video !== true);
  const drm = (item: Record<string, unknown>) =>
    (Array.isArray(item.drm_families) && item.drm_families.length > 0) ||
    Boolean(item.fair_play_key_uri || item.drm_track_type);
  const candidates = formats.filter((item) => !drm(item));
  const status = object(info.playability_status).status;
  const known = [
    'OK',
    'UNPLAYABLE',
    'LOGIN_REQUIRED',
    'ERROR',
    'LIVE_STREAM_OFFLINE',
    'CONTENT_CHECK_REQUIRED',
    'AGE_CHECK_REQUIRED',
  ];
  const mimeTypes = [
    ...new Set(
      candidates
        .map((item) => item.mime_type)
        .filter(
          (mime): mime is string =>
            typeof mime === 'string' &&
            /^audio\/[a-z0-9.+-]+(?:; codecs="[A-Za-z0-9., _-]+")?$/.test(mime),
        ),
    ),
  ];
  const direct = candidates.filter((item) => {
    if (typeof item.url !== 'string') return false;
    try {
      const url = new URL(item.url);
      return (
        url.protocol === 'https:' &&
        url.hostname.endsWith('.googlevideo.com') &&
        !url.username &&
        !url.password
      );
    } catch {
      return false;
    }
  });
  return {
    source: 'youtube',
    sourceId: requestedId,
    status:
      typeof status === 'string' && known.includes(status) ? status : 'UNKNOWN',
    audioOnlyFormats: formats.length,
    excludedDrmFormats: formats.filter(drm).length,
    directHttpsCandidates: direct.length,
    cipheredCandidates: candidates.filter((item) =>
      Boolean(item.signature_cipher || item.cipher),
    ).length,
    mimeTypes,
    delivery: {
      hasDashManifest: typeof streaming.dash_manifest_url === 'string',
      hasHlsManifest: typeof streaming.hls_manifest_url === 'string',
      hasSabrEndpoint: typeof streaming.server_abr_streaming_url === 'string',
    },
    audioPlaybackVerified: false,
  };
}
