import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { readPort } from '../src/config/env.js';

describe('API base', () => {
  it('responde health sin exponer la tecnología del servidor', async () => {
    const response = await request(createApp()).get('/api/v1/health');
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: 'ok' });
    expect(response.headers['x-powered-by']).toBeUndefined();
  });

  it('devuelve un error JSON para rutas inexistentes', async () => {
    const response = await request(createApp()).get('/api/v1/missing');
    expect(response.status).toBe(404);
    expect(response.body.error.code).toBe('NOT_FOUND');
  });

  it('rechaza JSON malformado sin revelar errores internos', async () => {
    const response = await request(createApp())
      .post('/api/v1/missing')
      .set('Content-Type', 'application/json')
      .send('{');
    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe('INVALID_REQUEST');
  });

  it('limita el tamaño de las solicitudes', async () => {
    const response = await request(createApp())
      .post('/api/v1/missing')
      .send({ value: 'a'.repeat(20_000) });
    expect(response.status).toBe(413);
  });
});

describe('configuración', () => {
  it('acepta puertos válidos', () => {
    expect(readPort('3000')).toBe(3000);
  });
  it.each(['', ' ', 'abc', '0', '65536', '3000.5'])(
    'rechaza PORT=%s',
    (port) => {
      expect(() => readPort(port)).toThrow();
    },
  );
});
