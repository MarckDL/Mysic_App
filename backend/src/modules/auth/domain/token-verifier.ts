export interface AuthIdentity {
  firebaseUid: string;
  provider: string;
  googleId?: string;
}

export interface TokenVerifier {
  verify(token: string): Promise<AuthIdentity>;
}

export class InvalidTokenError extends Error {}
export class AuthUnavailableError extends Error {}
