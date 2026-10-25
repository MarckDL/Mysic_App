import {
  AuthUnavailableError,
  InvalidTokenError,
  type AuthIdentity,
  type TokenVerifier,
} from '../../modules/auth/domain/token-verifier.js';

export interface VerifiedFirebaseToken {
  uid: string;
  email?: unknown;
  name?: unknown;
  picture?: unknown;
  firebase: {
    sign_in_provider: string;
    identities?: Record<string, unknown>;
  };
}

export interface FirebaseAuthClient {
  verifyIdToken(
    token: string,
    checkRevoked: boolean,
  ): Promise<VerifiedFirebaseToken>;
}

const invalidTokenCodes = new Set([
  'auth/argument-error',
  'auth/invalid-argument',
  'auth/invalid-id-token',
  'auth/id-token-expired',
  'auth/id-token-revoked',
  'auth/user-disabled',
  'auth/user-not-found',
]);

async function loadFirebaseAuth(): Promise<FirebaseAuthClient> {
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  if (!projectId || process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    // No se admiten tokens sin firma del emulador en la API real.
    throw new AuthUnavailableError('Firebase Admin no está configurado');
  }
  const { applicationDefault, getApps, initializeApp } =
    await import('firebase-admin/app');
  const { getAuth } = await import('firebase-admin/auth');
  const name = 'mysic-backend';
  const existing = getApps().find((app) => app.name === name);
  const app =
    existing ??
    initializeApp(
      {
        projectId,
        credential: applicationDefault(),
      },
      name,
    );
  if (app.options.projectId !== projectId) {
    throw new AuthUnavailableError('Proyecto Firebase inconsistente');
  }
  return getAuth(app);
}

function boundedText(value: unknown, limit: number): string | undefined {
  return typeof value === 'string' &&
    value.trim() &&
    value.trim().length <= limit
    ? value.trim()
    : undefined;
}

export function createFirebaseTokenVerifier(
  loadAuth: () => Promise<FirebaseAuthClient> = loadFirebaseAuth,
): TokenVerifier {
  return {
    async verify(token): Promise<AuthIdentity> {
      try {
        const auth = await loadAuth();
        // true comprueba revocación y cuentas deshabilitadas, además de firma/exp/aud/iss.
        const decoded = await auth.verifyIdToken(token, true);
        if (!decoded.uid || !decoded.firebase?.sign_in_provider) {
          throw new InvalidTokenError();
        }
        const googleIds = decoded.firebase.identities?.['google.com'];
        const email = boundedText(decoded.email, 320);
        const displayName = boundedText(decoded.name, 150);
        let photoUrl = boundedText(decoded.picture, 2048);
        if (photoUrl) {
          try {
            const url = new URL(photoUrl);
            if (url.protocol !== 'https:' || url.username || url.password)
              photoUrl = undefined;
          } catch {
            photoUrl = undefined;
          }
        }
        return {
          ...(email ? { email } : {}),
          ...(displayName ? { displayName } : {}),
          ...(photoUrl ? { photoUrl } : {}),
          firebaseUid: decoded.uid,
          provider: decoded.firebase.sign_in_provider,
          ...(Array.isArray(googleIds) &&
          typeof googleIds[0] === 'string' &&
          googleIds[0].length > 0 &&
          googleIds[0].length <= 255
            ? { googleId: googleIds[0] }
            : {}),
        };
      } catch (error) {
        if (error instanceof InvalidTokenError) throw error;
        const code =
          typeof error === 'object' && error !== null && 'code' in error
            ? error.code
            : undefined;
        if (typeof code === 'string' && invalidTokenCodes.has(code)) {
          throw new InvalidTokenError();
        }
        // Fallos de permisos, red o credenciales no se confunden con un token inválido.
        throw new AuthUnavailableError();
      }
    },
  };
}
