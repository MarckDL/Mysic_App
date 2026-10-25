import type { NextFunction, Request, Response } from 'express';
import { describe, expect, it, vi } from 'vitest';
import { requireAuth } from '../src/middleware/auth.middleware.js';
import { InvalidTokenError } from '../src/modules/auth/domain/token-verifier.js';

function context(header?: string) {
  const request = {
    get: () => header,
    body: { user_id: 'attacker' },
  } as unknown as Request;
  const response = {
    locals: {},
    setHeader: vi.fn(),
    status: vi.fn().mockReturnThis(),
    json: vi.fn(),
  };
  const next = vi.fn();
  return { request, response, next };
}

describe('requireAuth sin sockets', () => {
  it.each([
    undefined,
    '',
    'Basic abc',
    'Bearer',
    'Bearer ',
    'Bearer a b',
    'Bearer a,b',
    `Bearer ${'a'.repeat(16_385)}`,
  ])('rechaza una cabecera ausente o malformada (%#)', async (header) => {
    const { request, response, next } = context(header);
    const verify = vi.fn();
    await requireAuth({ verify })(
      request,
      response as unknown as Response,
      next as NextFunction,
    );
    expect(response.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
    expect(verify).not.toHaveBeenCalled();
  });

  it('usa el UID verificado, sin aceptar el propietario del body', async () => {
    const { request, response, next } = context('bearer token');
    const identity = { firebaseUid: 'verified-a', provider: 'google.com' };
    await requireAuth({ verify: async () => identity })(
      request,
      response as unknown as Response,
      next,
    );
    expect(response.locals).toEqual({ auth: identity });
    expect(next).toHaveBeenCalledOnce();
  });

  it('devuelve 403 a sesiones de otro proveedor', async () => {
    const { request, response, next } = context('Bearer token');
    await requireAuth({
      verify: async () => ({ firebaseUid: 'a', provider: 'password' }),
    })(request, response as unknown as Response, next);
    expect(response.status).toHaveBeenCalledWith(403);
    expect(next).not.toHaveBeenCalled();
  });

  it.each([
    [new InvalidTokenError('sensitive'), 401],
    [new Error('sensitive'), 503],
  ])('oculta errores internos (%#)', async (error, status) => {
    const { request, response, next } = context('Bearer token');
    await requireAuth({
      verify: async () => {
        throw error;
      },
    })(request, response as unknown as Response, next);
    expect(response.status).toHaveBeenCalledWith(status);
    expect(JSON.stringify(response.json.mock.calls)).not.toContain('sensitive');
    expect(next).not.toHaveBeenCalled();
  });
});
