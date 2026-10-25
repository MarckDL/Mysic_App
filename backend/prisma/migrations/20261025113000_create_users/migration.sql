BEGIN;

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "mysic";

-- CreateTable
CREATE TABLE "mysic"."users" (
    "id" UUID NOT NULL,
    "firebase_uid" VARCHAR(128) NOT NULL,
    "google_id" VARCHAR(255),
    "email" VARCHAR(320),
    "display_name" VARCHAR(150) NOT NULL,
    "photo_url" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_firebase_uid_key" ON "mysic"."users"("firebase_uid");

-- CreateIndex
CREATE UNIQUE INDEX "users_google_id_key" ON "mysic"."users"("google_id");

-- Los perfiles solo se consultan desde Express con un rol de backend autorizado.
-- Sin políticas, los roles sujetos a RLS no tienen acceso a las filas.
ALTER TABLE "mysic"."users" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON SCHEMA "mysic" FROM PUBLIC;
REVOKE ALL ON TABLE "mysic"."users" FROM PUBLIC;

COMMIT;
