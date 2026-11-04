import { describe, expect, it } from 'vitest';
import { assessYoutubeAudio } from '../src/infrastructure/music/youtube-audio-assessment.js';
const id = 'abcdefghijk';

describe('diagnóstico de capacidades de audio', () => {
  it('distingue metadatos de audio sin asumir reproducción', () => {
    expect(
      assessYoutubeAudio(
        { basic_info: { id }, playability_status: { status: 'UNPLAYABLE' } },
        id,
      ),
    ).toMatchObject({
      status: 'UNPLAYABLE',
      audioOnlyFormats: 0,
      audioPlaybackVerified: false,
    });
  });
  it('resume formatos sin revelar URLs, firmas ni datos internos', () => {
    const result = assessYoutubeAudio(
      {
        basic_info: { id },
        playability_status: { status: 'OK' },
        streaming_data: {
          adaptive_formats: [
            {
              has_audio: true,
              has_video: false,
              mime_type: 'audio/mp4; codecs="mp4a.40.2"',
              url: 'https://r1.googlevideo.com/videoplayback?sig=secret',
            },
            {
              has_audio: true,
              has_video: false,
              mime_type: 'audio/webm',
              signature_cipher: 'private-signature',
            },
            { has_audio: true, has_video: true, mime_type: 'video/mp4' },
            {
              has_audio: true,
              has_video: false,
              drm_families: ['DRM'],
              url: 'https://r1.googlevideo.com/protected',
            },
          ],
        },
      },
      id,
    );
    expect(result).toMatchObject({
      audioOnlyFormats: 3,
      excludedDrmFormats: 1,
      directHttpsCandidates: 1,
      cipheredCandidates: 1,
    });
    expect(JSON.stringify(result)).not.toContain('secret');
    expect(JSON.stringify(result)).not.toContain('private-signature');
    expect(result.audioPlaybackVerified).toBe(false);
  });
  it('rechaza identidad inconsistente y no acepta destinos arbitrarios', () => {
    expect(() =>
      assessYoutubeAudio({ basic_info: { id: '12345678901' } }, id),
    ).toThrow();
    expect(
      assessYoutubeAudio(
        {
          basic_info: { id },
          streaming_data: {
            formats: [
              {
                has_audio: true,
                url: 'https://googlevideo.com.evil.test/audio',
              },
              { has_audio: true, url: 'http://localhost/audio' },
            ],
          },
        },
        id,
      ).directHttpsCandidates,
    ).toBe(0);
  });
  it('identifica SABR sin confundirlo con URL de audio ni revelar el endpoint', () => {
    const result = assessYoutubeAudio(
      {
        basic_info: { id },
        playability_status: { status: 'OK' },
        streaming_data: {
          server_abr_streaming_url:
            'https://r1.googlevideo.com/videoplayback?token=private',
          adaptive_formats: [
            { has_audio: true, has_video: false, mime_type: 'audio/mp4' },
          ],
        },
      },
      id,
    );
    expect(result.status).toBe('OK');
    expect(result.audioOnlyFormats).toBe(1);
    expect(result.directHttpsCandidates).toBe(0);
    expect(result.delivery.hasSabrEndpoint).toBe(true);
    expect(result.audioPlaybackVerified).toBe(false);
    expect(JSON.stringify(result)).not.toContain('private');
  });
});
