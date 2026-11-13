export interface RatingStatus {
  myRating: number | null;
  ratingAverage: number | null;
  ratingCount: number;
}

export class RatingUserNotSyncedError extends Error {}
export class RatingTrackNotFoundError extends Error {}
export class RatingDatabaseError extends Error {}
