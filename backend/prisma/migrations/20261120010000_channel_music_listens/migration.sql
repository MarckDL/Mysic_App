BEGIN;
ALTER TABLE "mysic"."external_music_connections" ADD COLUMN "mysicHistoryPaused" BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN "mysicActivityEpoch" INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN "mysicLibraryId" UUID;

CREATE TABLE "mysic"."channel_music_listens" (
    "userId" UUID NOT NULL,
    "generation" UUID NOT NULL,
    "listenId" UUID NOT NULL,
    "videoId" VARCHAR(11) NOT NULL,
    "listenedMs" INTEGER NOT NULL CHECK ("listenedMs" BETWEEN 1 AND 86400000),
    "playedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "channel_music_listens_pkey" PRIMARY KEY ("userId", "generation", "listenId"),
    CONSTRAINT "channel_music_listens_userId_fkey" FOREIGN KEY ("userId")
        REFERENCES "mysic"."external_music_connections"("userId") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "channel_music_listens_userId_generation_playedAt_listenId_idx"
    ON "mysic"."channel_music_listens" ("userId", "generation", "playedAt", "listenId");

ALTER TABLE mysic.channel_music_listens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE mysic.channel_music_listens FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON TABLE mysic.channel_music_listens FROM anon;
    END IF;
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        REVOKE ALL ON TABLE mysic.channel_music_listens FROM authenticated;
    END IF;
END $$;
COMMIT;
