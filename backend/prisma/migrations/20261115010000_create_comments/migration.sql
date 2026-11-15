BEGIN;
-- CreateEnum
CREATE TYPE "mysic"."comment_status" AS ENUM ('visible', 'hidden', 'deleted');

-- CreateEnum
CREATE TYPE "mysic"."comment_report_reason" AS ENUM ('spam', 'harassment', 'other');

-- CreateEnum
CREATE TYPE "mysic"."comment_report_status" AS ENUM ('pending', 'dismissed', 'hidden', 'deleted');

-- CreateTable
CREATE TABLE "mysic"."comments" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "track_id" UUID NOT NULL,
    "body" TEXT NOT NULL,
    "status" "mysic"."comment_status" NOT NULL DEFAULT 'visible',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "comments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "mysic"."comment_reports" (
    "comment_id" UUID NOT NULL,
    "reporter_id" UUID NOT NULL,
    "reason" "mysic"."comment_report_reason" NOT NULL,
    "status" "mysic"."comment_report_status" NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "moderator_id" UUID,
    "resolved_at" TIMESTAMPTZ(3),

    CONSTRAINT "comment_reports_pkey" PRIMARY KEY ("comment_id","reporter_id")
);

-- CreateIndex
CREATE INDEX "comments_track_id_status_created_at_id_idx" ON "mysic"."comments"("track_id", "status", "created_at", "id");

-- CreateIndex
CREATE INDEX "comments_user_id_idx" ON "mysic"."comments"("user_id");

-- CreateIndex
CREATE INDEX "comment_reports_status_comment_id_created_at_idx" ON "mysic"."comment_reports"("status", "comment_id", "created_at");

-- CreateIndex
CREATE INDEX "comment_reports_reporter_id_idx" ON "mysic"."comment_reports"("reporter_id");

-- CreateIndex
CREATE INDEX "comment_reports_moderator_id_idx" ON "mysic"."comment_reports"("moderator_id");

-- AddForeignKey
ALTER TABLE "mysic"."comments" ADD CONSTRAINT "comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mysic"."comments" ADD CONSTRAINT "comments_track_id_fkey" FOREIGN KEY ("track_id") REFERENCES "mysic"."tracks"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mysic"."comment_reports" ADD CONSTRAINT "comment_reports_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "mysic"."comments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mysic"."comment_reports" ADD CONSTRAINT "comment_reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mysic"."comment_reports" ADD CONSTRAINT "comment_reports_moderator_id_fkey" FOREIGN KEY ("moderator_id") REFERENCES "mysic"."users"("id") ON DELETE SET NULL ON UPDATE CASCADE;


ALTER TABLE mysic.comments ADD CONSTRAINT comments_body_length
CHECK (char_length(body) BETWEEN 1 AND 500 AND body ~ '[^[:space:]]');
ALTER TABLE mysic.comment_reports ADD CONSTRAINT comment_reports_resolution
CHECK ((status = 'pending') = (resolved_at IS NULL) AND
       (status <> 'pending' OR moderator_id IS NULL));

ALTER TABLE mysic.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE mysic.comment_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE mysic.comments, mysic.comment_reports FROM PUBLIC;
DO $$
BEGIN
  IF to_regrole('anon') IS NOT NULL THEN
    REVOKE ALL ON TABLE mysic.comments, mysic.comment_reports FROM anon;
  END IF;
  IF to_regrole('authenticated') IS NOT NULL THEN
    REVOKE ALL ON TABLE mysic.comments, mysic.comment_reports FROM authenticated;
  END IF;
END
$$;

COMMIT;
