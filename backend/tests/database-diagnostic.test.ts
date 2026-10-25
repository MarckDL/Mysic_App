import { describe, expect, it } from 'vitest';
import { databaseDiagnostic } from '../src/infrastructure/database/database-diagnostic.js';

describe('diagnóstico local de base', () => {
  it('identifica un certificado anidado sin revelar URL ni contraseña', () => {
    const result = databaseDiagnostic({
      meta: {
        driverAdapterError: {
          cause: {
            originalMessage:
              'self-signed certificate postgres://user:secret@host',
          },
        },
      },
    });
    expect(result).toContain('TLS:');
    expect(result).not.toContain('secret');
    expect(result).not.toContain('host');
  });
  it('distingue DNS de autenticación', () => {
    expect(
      databaseDiagnostic(new Error('getaddrinfo ENOTFOUND secret-host')),
    ).toContain('DNS:');
    expect(databaseDiagnostic({ code: '28P01', message: 'private' })).toContain(
      'Autenticación:',
    );
  });
  it('soporta causas circulares y oculta errores desconocidos', () => {
    const error: { cause?: unknown; message: string } = {
      message: 'private-secret',
    };
    error.cause = error;
    expect(databaseDiagnostic(error)).not.toContain('private-secret');
  });
});
