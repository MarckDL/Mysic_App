import 'package:mysic/features/ytm/data/ytm_client.dart';
import 'package:mysic/features/ytm/data/ytm_session.dart';

/// Un cliente de YouTube Music que no se usa: las pruebas sustituyen los
/// métodos de `MusicModeClient` que hablarían con la red.
YtmClient ytmTestClient() => YtmClient(const YtmSession('SAPISID=test'));
