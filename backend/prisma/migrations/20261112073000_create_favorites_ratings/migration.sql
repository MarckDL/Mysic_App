BEGIN;

CREATE TABLE "mysic"."favorites" (
    "user_id" UUID NOT NULL,
    "track_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "favorites_pkey" PRIMARY KEY ("user_id", "track_id")
);

CREATE TABLE "mysic"."ratings" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "track_id" UUID NOT NULL,
    "score" SMALLINT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ratings_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "ratings_score_check" CHECK ("score" BETWEEN 1 AND 5)
);

CREATE INDEX "favorites_user_id_created_at_idx"
ON "mysic"."favorites"("user_id", "created_at");
CREATE INDEX "favorites_track_id_idx"
ON "mysic"."favorites"("track_id");
CREATE UNIQUE INDEX "ratings_user_id_track_id_key"
ON "mysic"."ratings"("user_id", "track_id");
CREATE INDEX "ratings_track_id_idx"
ON "mysic"."ratings"("track_id");

ALTER TABLE "mysic"."favorites"
ADD CONSTRAINT "favorites_user_id_fkey" FOREIGN KEY ("user_id")
REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "mysic"."favorites"
ADD CONSTRAINT "favorites_track_id_fkey" FOREIGN KEY ("track_id")
REFERENCES "mysic"."tracks"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "mysic"."ratings"
ADD CONSTRAINT "ratings_user_id_fkey" FOREIGN KEY ("user_id")
REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "mysic"."ratings"
ADD CONSTRAINT "ratings_track_id_fkey" FOREIGN KEY ("track_id")
REFERENCES "mysic"."tracks"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "mysic"."favorites" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "mysic"."ratings" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "mysic"."favorites" FROM PUBLIC;
REVOKE ALL ON TABLE "mysic"."ratings" FROM PUBLIC;

COMMIT;
