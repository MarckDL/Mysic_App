import {
  DatabaseUnavailableError,
  UserConflictError,
  type UserRepository,
  type VerifiedProfile,
} from '../../modules/users/domain/user-repository.js';
import { getDatabase } from './prisma.js';

function translateError(error: unknown): never {
  if (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === 'P2002'
  ) {
    throw new UserConflictError();
  }
  throw new DatabaseUnavailableError();
}

export class PrismaUserRepository implements UserRepository {
  async sync(profile: VerifiedProfile) {
    try {
      const { firebaseUid, ...fields } = profile;
      // Una sola sentencia UPSERT: las llamadas concurrentes no duplican el UID.
      return await getDatabase().user.upsert({
        where: { firebaseUid },
        create: {
          ...fields,
          firebaseUid,
          displayName: fields.displayName ?? 'Usuario Mysic',
        },
        update: { ...fields, firebaseUid },
      });
    } catch (error) {
      translateError(error);
    }
  }

  async findByFirebaseUid(firebaseUid: string) {
    try {
      return await getDatabase().user.findUnique({ where: { firebaseUid } });
    } catch (error) {
      translateError(error);
    }
  }
}
