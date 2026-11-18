import type { Express } from 'express';

export function installYoutubeAppLinks(
  app: Express,
  fingerprints = process.env.YOUTUBE_ANDROID_SHA256,
) {
  if (!fingerprints?.trim()) return;
  const values = [
    ...new Set(fingerprints.split(',').map((x) => x.trim().toUpperCase())),
  ];
  if (!values.every((x) => /^(?:[A-F0-9]{2}:){31}[A-F0-9]{2}$/.test(x)))
    throw new Error('Invalid Android signing certificate fingerprint');
  app.get('/.well-known/assetlinks.json', (_req, res) =>
    res.json([
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: 'com.mysic.mysic',
          sha256_cert_fingerprints: values,
        },
      },
    ]),
  );
  app.get('/library/youtube/return', (_req, res) => {
    res
      .set({
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer',
        'Content-Security-Policy':
          "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
      })
      .type('html')
      .send(
        '<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Volver a Mysic</title><h1>Vuelve a Mysic</h1><p>Abre Biblioteca y toca Comprobar vinculación para ver el resultado de Google.</p></html>',
      );
  });
}
