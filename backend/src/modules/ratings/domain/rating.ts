export interface RatingSummary {
  myScore: number | null;
  averageScore: number | null;
  ratingCount: number;
}

export class RatingUserNotSyncedError extends Error {}
export class RatingTrackUnavailableError extends Error {}
export class RatingDatabaseError extends Error {}
