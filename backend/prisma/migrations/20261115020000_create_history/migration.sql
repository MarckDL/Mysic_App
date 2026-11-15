CREATE TABLE mysic.listening_history (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES mysic.users(id) ON DELETE CASCADE,
 track_id UUID NOT NULL REFERENCES mysic.tracks(id) ON DELETE RESTRICT,
 playback_session_id UUID NOT NULL UNIQUE,
 started_at TIMESTAMPTZ(3) NOT NULL,
 listened_ms BIGINT NOT NULL CHECK (listened_ms >= 0 AND listened_ms <= 86400000),
 completed BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX listening_history_user_id_started_at_id_idx ON mysic.listening_history(user_id, started_at, id);
CREATE INDEX listening_history_user_id_track_id_idx ON mysic.listening_history(user_id, track_id);
ALTER TABLE mysic.listening_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON mysic.listening_history FROM PUBLIC;
DO $$ BEGIN
 IF EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN REVOKE ALL ON mysic.listening_history FROM anon; END IF;
 IF EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN REVOKE ALL ON mysic.listening_history FROM authenticated; END IF;
END $$;
