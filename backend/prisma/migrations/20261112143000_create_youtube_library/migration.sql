BEGIN;

CREATE TABLE "mysic"."youtube_connections" (
  "user_id" UUID PRIMARY KEY,
  "channel_id" VARCHAR(255) NOT NULL,
  "display_name" VARCHAR(255) NOT NULL,
  "avatar_url" TEXT,
  "connected_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "last_synced_at" TIMESTAMPTZ(6) NOT NULL,
  CONSTRAINT "youtube_connections_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "mysic"."youtube_remote_playlists" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "user_id" UUID NOT NULL,
  "external_id" VARCHAR(255) NOT NULL,
  "title" VARCHAR(500) NOT NULL,
  "thumbnail_url" TEXT,
  "item_count" INTEGER NOT NULL,
  CONSTRAINT "youtube_remote_playlists_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "mysic"."youtube_connections"("user_id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "youtube_remote_playlists_item_count_check" CHECK ("item_count" >= 0),
  CONSTRAINT "youtube_remote_playlists_user_id_external_id_key" UNIQUE ("user_id", "external_id")
);
CREATE INDEX "youtube_remote_playlists_user_id_title_idx" ON "mysic"."youtube_remote_playlists"("user_id", "title");

CREATE TABLE "mysic"."youtube_remote_playlist_tracks" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "playlist_id" UUID NOT NULL,
  "track_id" UUID NOT NULL,
  "external_item_id" VARCHAR(255) NOT NULL,
  "position" INTEGER NOT NULL,
  CONSTRAINT "youtube_remote_playlist_tracks_playlist_id_fkey" FOREIGN KEY ("playlist_id")
    REFERENCES "mysic"."youtube_remote_playlists"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "youtube_remote_playlist_tracks_track_id_fkey" FOREIGN KEY ("track_id")
    REFERENCES "mysic"."tracks"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "youtube_remote_playlist_tracks_position_check" CHECK ("position" >= 0),
  CONSTRAINT "youtube_remote_playlist_tracks_playlist_id_external_item_id_key" UNIQUE ("playlist_id", "external_item_id"),
  CONSTRAINT "youtube_remote_playlist_tracks_playlist_id_position_key" UNIQUE ("playlist_id", "position")
);
CREATE INDEX "youtube_remote_playlist_tracks_track_id_idx" ON "mysic"."youtube_remote_playlist_tracks"("track_id");

CREATE TABLE "mysic"."youtube_remote_likes" (
  "user_id" UUID NOT NULL,
  "track_id" UUID NOT NULL,
  PRIMARY KEY ("user_id", "track_id"),
  CONSTRAINT "youtube_remote_likes_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "mysic"."youtube_connections"("user_id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "youtube_remote_likes_track_id_fkey" FOREIGN KEY ("track_id")
    REFERENCES "mysic"."tracks"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX "youtube_remote_likes_track_id_idx" ON "mysic"."youtube_remote_likes"("track_id");

CREATE TABLE "mysic"."youtube_remote_subscriptions" (
  "user_id" UUID NOT NULL,
  "channel_id" VARCHAR(255) NOT NULL,
  "title" VARCHAR(500) NOT NULL,
  "thumbnail_url" TEXT,
  PRIMARY KEY ("user_id", "channel_id"),
  CONSTRAINT "youtube_remote_subscriptions_user_id_fkey" FOREIGN KEY ("user_id")
    REFERENCES "mysic"."youtube_connections"("user_id") ON DELETE CASCADE ON UPDATE CASCADE
);

ALTER TABLE "mysic"."youtube_connections" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "mysic"."youtube_remote_playlists" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "mysic"."youtube_remote_playlist_tracks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "mysic"."youtube_remote_likes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "mysic"."youtube_remote_subscriptions" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "mysic"."youtube_connections" FROM PUBLIC;
REVOKE ALL ON TABLE "mysic"."youtube_remote_playlists" FROM PUBLIC;
REVOKE ALL ON TABLE "mysic"."youtube_remote_playlist_tracks" FROM PUBLIC;
REVOKE ALL ON TABLE "mysic"."youtube_remote_likes" FROM PUBLIC;
REVOKE ALL ON TABLE "mysic"."youtube_remote_subscriptions" FROM PUBLIC;

COMMIT;
