import type { Track } from '../../catalog/domain/music-provider.js';

export const reportReasons = ['spam', 'harassment', 'other'] as const;
export type ReportReason = (typeof reportReasons)[number];
export type ModerationAction = 'hide' | 'dismiss';

export interface CommentItem {
  id: string;
  body: string;
  authorName: string;
  createdAt: Date;
  updatedAt: Date;
  isMine: boolean;
}

export interface ModerationItem extends Omit<CommentItem, 'isMine'> {
  firstReportAt: Date;
  reasons: ReportReason[];
}

export interface PagePosition {
  date: Date;
  id: string;
}

export interface PageRequest {
  limit: number;
  after?: PagePosition;
}

export interface CommentRepository {
  findUserId(firebaseUid: string): Promise<string | null>;
  list(
    userId: string,
    sourceId: string,
    page: PageRequest,
  ): Promise<CommentItem[]>;
  create(userId: string, track: Track, body: string): Promise<CommentItem>;
  edit(userId: string, id: string, body: string): Promise<CommentItem>;
  remove(userId: string, id: string): Promise<void>;
  report(userId: string, id: string, reason: ReportReason): Promise<void>;
  queue(page: PageRequest): Promise<ModerationItem[]>;
  resolve(userId: string, id: string, action: ModerationAction): Promise<void>;
}

const errors = {
  FORBIDDEN: [403, 'No tienes permiso para realizar esta acción'],
  COMMENT_NOT_FOUND: [404, 'Comentario no disponible'],
  USER_NOT_SYNCED: [404, 'Sincroniza tu perfil para continuar'],
  TRACK_NOT_FOUND: [404, 'Pista no encontrada'],
  REPORTS_ALREADY_RESOLVED: [409, 'Los reportes ya fueron resueltos'],
  CATALOG_TIMEOUT: [504, 'El catálogo tardó demasiado en responder'],
  CATALOG_UNAVAILABLE: [503, 'No se pudo consultar el catálogo'],
} as const;

export class CommentError extends Error {
  readonly status: number;

  constructor(readonly code: keyof typeof errors) {
    const [status, message] = errors[code];
    super(message);
    this.status = status;
  }
}
