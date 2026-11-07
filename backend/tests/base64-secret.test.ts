import { afterEach, describe, expect, it, vi } from 'vitest';
import { readBase64Secret } from '../src/infrastructure/config/base64-secret.js';

describe('readBase64Secret', () => {
  afterEach(() => vi.unstubAllEnvs());

  it('devuelve undefined cuando la variable no existe', () => {
    vi.stubEnv('TEST_SECRET', '');
    expect(readBase64Secret('TEST_SECRET')).toBeUndefined();
  });

  it('decodifica contenido UTF-8 sin registrarlo', () => {
    vi.stubEnv(
      'TEST_SECRET',
      Buffer.from('contenido\nseguro', 'utf8').toString('base64'),
    );
    expect(readBase64Secret('TEST_SECRET')).toBe('contenido\nseguro');
  });

  it.each(['no-es-base64', '====', 'YWJjZA='])('rechaza %s', (value) => {
    vi.stubEnv('TEST_SECRET', value);
    expect(() => readBase64Secret('TEST_SECRET')).toThrow(
      'TEST_SECRET no contiene Base64 válido',
    );
  });
});
