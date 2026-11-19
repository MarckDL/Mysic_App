import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { installYoutubeAppLinks } from '../src/modules/integrations/youtube/android-links.js';

const cert = Array(32).fill('AB').join(':');
describe('Android App Links del piloto', () => {
  it('publica únicamente las firmas configuradas para el paquete Mysic', async () => {
    const app = express();
    installYoutubeAppLinks(app, cert.toLowerCase() + ',' + cert);
    const manifest = await request(app)
      .get('/.well-known/assetlinks.json')
      .expect(200);
    expect(manifest.body).toEqual([
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: 'com.mysic.mysic',
          sha256_cert_fingerprints: [cert],
        },
      },
    ]);
    const page = await request(app)
      .get('/library/youtube/return?sample=fixture')
      .expect(200);
    expect(page.headers['cache-control']).toBe('no-store');
    expect(page.text).toContain('Comprobar vinculación');
    expect(page.text).not.toContain('fixture');
  });
  it('sin firma no publica asociación y una huella incompleta se rechaza', async () => {
    const app = express();
    installYoutubeAppLinks(app, '');
    await request(app).get('/.well-known/assetlinks.json').expect(404);
    expect(() => installYoutubeAppLinks(app, 'AB:00')).toThrow('fingerprint');
  });
});
