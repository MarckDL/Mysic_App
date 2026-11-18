CREATE TABLE "mysic"."music_imports" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "fingerprint" VARCHAR(64) NOT NULL,
    "name" VARCHAR(150) NOT NULL,
    "items" JSONB NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "confirmed_at" TIMESTAMPTZ(3),
    "playlist_id" UUID,
    "saved_count" INTEGER NOT NULL DEFAULT 0,
    "skipped_count" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "music_imports_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "music_imports_counts_check" CHECK ("saved_count" BETWEEN 0 AND 500 AND "skipped_count" BETWEEN 0 AND 500),
    CONSTRAINT "music_imports_items_check" CHECK (jsonb_typeof("items") = 'array' AND jsonb_array_length("items") <= 500)
);
CREATE INDEX "music_imports_user_id_expires_at_idx" ON "mysic"."music_imports"("user_id", "expires_at");
CREATE INDEX "music_imports_confirmed_at_expires_at_idx" ON "mysic"."music_imports"("confirmed_at", "expires_at");
CREATE INDEX "music_imports_playlist_id_idx" ON "mysic"."music_imports"("playlist_id");
ALTER TABLE "mysic"."music_imports" ADD CONSTRAINT "music_imports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "mysic"."music_imports" ADD CONSTRAINT "music_imports_playlist_id_fkey" FOREIGN KEY ("playlist_id") REFERENCES "mysic"."playlists"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "mysic"."music_imports" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON "mysic"."music_imports" FROM PUBLIC;
DO $$ BEGIN
 IF EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN REVOKE ALL ON mysic.music_imports FROM anon; END IF;
 IF EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN REVOKE ALL ON mysic.music_imports FROM authenticated; END IF;
END $$;
