import type { AuthIdentity } from '../../auth/domain/token-verifier.js';
import type { UserRepository } from '../domain/user-repository.js';

export class UserService {
  constructor(private readonly repository: UserRepository) {}

  sync(identity: AuthIdentity) {
    return this.repository.sync({
      firebaseUid: identity.firebaseUid,
      ...(identity.googleId ? { googleId: identity.googleId } : {}),
      ...(identity.email ? { email: identity.email } : {}),
      ...(identity.displayName ? { displayName: identity.displayName } : {}),
      ...(identity.photoUrl ? { photoUrl: identity.photoUrl } : {}),
    });
  }

  me(identity: AuthIdentity) {
    return this.repository.findByFirebaseUid(identity.firebaseUid);
  }
}
