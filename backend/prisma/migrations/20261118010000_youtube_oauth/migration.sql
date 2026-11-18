-- CreateTable
CREATE TABLE "mysic"."external_music_link_attempts" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "requestKey" UUID NOT NULL,
    "status" TEXT NOT NULL,
    "reason" TEXT,
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "launchHash" TEXT,
    "launchBox" TEXT,
    "stateHash" TEXT,
    "cookieHash" TEXT,
    "nonceHash" TEXT,
    "verifierBox" TEXT,
    "returnHash" TEXT,
    "forceConsent" BOOLEAN NOT NULL DEFAULT false,
    "subject" TEXT,
    "channelId" TEXT,
    "channelTitle" TEXT,
    "refreshBox" TEXT,
    "scopes" TEXT,

    CONSTRAINT "external_music_link_attempts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "mysic"."external_music_connections" (
    "userId" UUID NOT NULL,
    "subject" TEXT NOT NULL,
    "channelId" TEXT NOT NULL,
    "channelTitle" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "generation" UUID NOT NULL,
    "refreshBox" TEXT,
    "scopes" TEXT NOT NULL,
    "connectedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "checkedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lease" UUID,
    "leaseUntil" TIMESTAMPTZ(3),

    CONSTRAINT "external_music_connections_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "mysic"."external_music_revocations" (
    "id" UUID NOT NULL,
    "subject" TEXT NOT NULL,
    "ownerId" UUID NOT NULL,
    "refreshBox" TEXT NOT NULL,
    "tries" INTEGER NOT NULL DEFAULT 0,
    "nextAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "external_music_revocations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "external_music_link_attempts_launchHash_key" ON "mysic"."external_music_link_attempts"("launchHash");

-- CreateIndex
CREATE UNIQUE INDEX "external_music_link_attempts_stateHash_key" ON "mysic"."external_music_link_attempts"("stateHash");

-- CreateIndex
CREATE INDEX "external_music_link_attempts_expiresAt_idx" ON "mysic"."external_music_link_attempts"("expiresAt");

-- CreateIndex
CREATE INDEX "external_music_link_attempts_subject_idx" ON "mysic"."external_music_link_attempts"("subject");

-- CreateIndex
CREATE UNIQUE INDEX "external_music_link_attempts_userId_requestKey_key" ON "mysic"."external_music_link_attempts"("userId", "requestKey");

-- CreateIndex
CREATE UNIQUE INDEX "external_music_connections_subject_key" ON "mysic"."external_music_connections"("subject");

-- CreateIndex
CREATE UNIQUE INDEX "external_music_connections_generation_key" ON "mysic"."external_music_connections"("generation");

-- CreateIndex
CREATE INDEX "external_music_connections_status_checkedAt_idx" ON "mysic"."external_music_connections"("status", "checkedAt");

-- CreateIndex
CREATE UNIQUE INDEX "external_music_revocations_subject_key" ON "mysic"."external_music_revocations"("subject");

-- CreateIndex
CREATE INDEX "external_music_revocations_nextAt_idx" ON "mysic"."external_music_revocations"("nextAt");

-- CreateIndex
CREATE INDEX "external_music_revocations_ownerId_idx" ON "mysic"."external_music_revocations"("ownerId");

-- AddForeignKey
ALTER TABLE "mysic"."external_music_link_attempts" ADD CONSTRAINT "external_music_link_attempts_userId_fkey" FOREIGN KEY ("userId") REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mysic"."external_music_connections" ADD CONSTRAINT "external_music_connections_userId_fkey" FOREIGN KEY ("userId") REFERENCES "mysic"."users"("id") ON DELETE CASCADE ON UPDATE CASCADE;


ALTER TABLE mysic.external_music_link_attempts ADD CHECK (status IN ('created','authorizing','exchanging','awaiting_confirmation','confirmed','failed','denied','expired','canceled'));
ALTER TABLE mysic.external_music_connections ADD CHECK (status IN ('linked','reauthorization_required'));
ALTER TABLE mysic.external_music_connections ADD CHECK ((status = 'linked') = ("refreshBox" IS NOT NULL));
CREATE UNIQUE INDEX external_music_one_live_attempt ON mysic.external_music_link_attempts ("userId")
  WHERE status IN ('created','authorizing','exchanging','awaiting_confirmation');
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['external_music_link_attempts','external_music_connections','external_music_revocations'] LOOP
    EXECUTE format('ALTER TABLE mysic.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON TABLE mysic.%I FROM PUBLIC',t);
    IF EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN EXECUTE format('REVOKE ALL ON TABLE mysic.%I FROM anon',t); END IF;
    IF EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN EXECUTE format('REVOKE ALL ON TABLE mysic.%I FROM authenticated',t); END IF;
  END LOOP;
END $$;
