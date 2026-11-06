import {
  DatabaseUnavailableError,
  UserConflictError,
  type UserRepository,
  type VerifiedProfile,
} from '../../modules/users/domain/user-repository.js';
import { getDatabase } from './prisma.js';

function isUniqueConstraintError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === 'P2002'
  );
}

function translateError(error: unknown): never {
  if (isUniqueConstraintError(error)) {
    throw new UserConflictError();
  }
  throw new DatabaseUnavailableError();
}

export class PrismaUserRepository implements UserRepository {
  async sync(profile: VerifiedProfile) {
    const { firebaseUid, ...fields } = profile;
    try {
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
      // Dos altas simultáneas con el mismo UID y google_id pueden competir por
      // ambas restricciones únicas. PostgreSQL resuelve el UID del upsert, pero
      // una de las sentencias todavía puede recibir P2002 por google_id. Una vez
      // confirmado que el UID ganador representa la misma identidad, se aplica
      // la actualización sobre ese registro. Un google_id de otro usuario sigue
      // siendo un conflicto y nunca provoca una fusión de cuentas.
      if (isUniqueConstraintError(error)) {
        try {
          const database = getDatabase();
          const existing = await database.user.findUnique({
            where: { firebaseUid },
          });
          const googleIdMatches =
            fields.googleId === undefined ||
            existing?.googleId === null ||
            existing?.googleId === fields.googleId;
          if (!existing || !googleIdMatches) throw new UserConflictError();
          return await database.user.update({
            where: { firebaseUid },
            data: { ...fields, firebaseUid },
          });
        } catch (recoveryError) {
          if (recoveryError instanceof UserConflictError) throw recoveryError;
          translateError(recoveryError);
        }
      }
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
