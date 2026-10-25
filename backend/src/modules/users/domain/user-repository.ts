export interface UserProfile {
  id: string;
  firebaseUid: string;
  googleId: string | null;
  email: string | null;
  displayName: string;
  photoUrl: string | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface VerifiedProfile {
  firebaseUid: string;
  googleId?: string;
  email?: string;
  displayName?: string;
  photoUrl?: string;
}

export interface UserRepository {
  sync(profile: VerifiedProfile): Promise<UserProfile>;
  findByFirebaseUid(firebaseUid: string): Promise<UserProfile | null>;
}

export class UserConflictError extends Error {}
export class DatabaseUnavailableError extends Error {}
