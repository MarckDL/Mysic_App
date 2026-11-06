BEGIN;

-- Flutter nunca accede a estas tablas mediante la Data API. Sin políticas,
-- cualquier rol sujeto a RLS queda sin acceso; Express usa el rol de backend.
ALTER TABLE "mysic"."tracks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "mysic"."playlists" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "mysic"."playlist_tracks" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "mysic"."tracks" FROM PUBLIC;
REVOKE ALL ON TABLE "mysic"."playlists" FROM PUBLIC;
REVOKE ALL ON TABLE "mysic"."playlist_tracks" FROM PUBLIC;

COMMIT;
