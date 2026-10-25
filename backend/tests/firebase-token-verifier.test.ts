import { describe, expect, it, vi } from 'vitest';
import { createFirebaseTokenVerifier } from '../src/infrastructure/firebase/firebase-token-verifier.js';
import {
  AuthUnavailableError,
  InvalidTokenError,
} from '../src/modules/auth/domain/token-verifier.js';

describe('Firebase TokenVerifier', () => {
  it('solicita comprobación de revocación y devuelve solo identidad verificada', async () => {
    const verifyIdToken = vi.fn().mockResolvedValue({
      uid: 'firebase-a',
      firebase: {
        sign_in_provider: 'google.com',
        identities: { 'google.com': ['google-a'] },
      },
      email: 'not-returned@example.test',
    });
    const verifier = createFirebaseTokenVerifier(async () => ({
      verifyIdToken,
    }));
    await expect(verifier.verify('id-token')).resolves.toEqual({
      firebaseUid: 'firebase-a',
      provider: 'google.com',
      googleId: 'google-a',
    });
    expect(verifyIdToken).toHaveBeenCalledWith('id-token', true);
  });

  it.each([
    'auth/argument-error',
    'auth/invalid-argument',
    'auth/invalid-id-token',
    'auth/id-token-expired',
    'auth/id-token-revoked',
    'auth/user-disabled',
    'auth/user-not-found',
  ])('rechaza %s', async (code) => {
    const verifier = createFirebaseTokenVerifier(async () => ({
      verifyIdToken: vi.fn().mockRejectedValue({ code }),
    }));
    await expect(verifier.verify('bad-token')).rejects.toBeInstanceOf(
      InvalidTokenError,
    );
  });

  it('distingue fallos operativos de credenciales inválidas', async () => {
    const verifier = createFirebaseTokenVerifier(async () => {
      throw new Error('secret');
    });
    await expect(verifier.verify('token')).rejects.toBeInstanceOf(
      AuthUnavailableError,
    );
  });

  it('rechaza claims incompletos', async () => {
    const verifier = createFirebaseTokenVerifier(async () => ({
      verifyIdToken: vi.fn().mockResolvedValue({ uid: '', firebase: {} }),
    }));
    await expect(verifier.verify('token')).rejects.toBeInstanceOf(
      InvalidTokenError,
    );
  });

  it('no acepta el emulador Firebase con tokens sin firma', async () => {
    vi.stubEnv('FIREBASE_PROJECT_ID', 'test-project');
    vi.stubEnv('FIREBASE_AUTH_EMULATOR_HOST', '127.0.0.1:9099');
    try {
      await expect(
        createFirebaseTokenVerifier().verify('token'),
      ).rejects.toBeInstanceOf(AuthUnavailableError);
    } finally {
      vi.unstubAllEnvs();
    }
  });

  it('no habilita autenticación sin un proyecto configurado', async () => {
    vi.stubEnv('FIREBASE_PROJECT_ID', '');
    try {
      await expect(
        createFirebaseTokenVerifier().verify('token'),
      ).rejects.toBeInstanceOf(AuthUnavailableError);
    } finally {
      vi.unstubAllEnvs();
    }
  });
});
