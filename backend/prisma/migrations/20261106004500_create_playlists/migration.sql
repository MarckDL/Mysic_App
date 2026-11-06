CREATE TYPE "mysic"."playlist_visibility" AS ENUM ('private', 'public');

CREATE TABLE "mysic"."tracks" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "source" VARCHAR(50) NOT NULL,
    "source_id" VARCHAR(255) NOT NULL,
    "title" VARCHAR(500) NOT NULL,
    "artist_name" VARCHAR(255) NOT NULL,
    "duration_seconds" INTEGER,
    "thumbnail_url" TEXT,
    "metadata_updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "tracks_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "tracks_duration_seconds_check"
      CHECK ("duration_seconds" IS NULL OR "duration_seconds" > 0)
);

CREATE TABLE "mysic"."playlists" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "name" VARCHAR(150) NOT NULL,
    "description" TEXT,
    "visibility" "mysic"."playlist_visibility" NOT NULL DEFAULT 'private',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "playlists_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "playlists_name_check" CHECK (char_length(btrim("name")) > 0),
    CONSTRAINT "playlists_description_check"
      CHECK ("description" IS NULL OR char_length("description") <= 2000)
);

CREATE TABLE "mysic"."playlist_tracks" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "playlist_id" UUID NOT NULL,
    "track_id" UUID NOT NULL,
    "position" INTEGER NOT NULL,
    "added_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "playlist_tracks_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "playlist_tracks_position_check" CHECK ("position" >= 0)
);

CREATE UNIQUE INDEX "tracks_source_source_id_key"
ON "mysic"."tracks"("source", "source_id");
CREATE INDEX "playlists_user_id_updated_at_idx"
ON "mysic"."playlists"("user_id", "updated_at");
CREATE UNIQUE INDEX "playlist_tracks_playlist_id_position_key"
ON "mysic"."playlist_tracks"("playlist_id", "position");
CREATE INDEX "playlist_tracks_track_id_idx"
ON "mysic"."playlist_tracks"("track_id");

ALTER TABLE "mysic"."playlists"
ADD CONSTRAINT "playlists_user_id_fkey" FOREIGN KEY ("user_id")
REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "mysic"."playlist_tracks"
ADD CONSTRAINT "playlist_tracks_playlist_id_fkey" FOREIGN KEY ("playlist_id")
REFERENCES "mysic"."playlists"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "mysic"."playlist_tracks"
ADD CONSTRAINT "playlist_tracks_track_id_fkey" FOREIGN KEY ("track_id")
REFERENCES "mysic"."tracks"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
