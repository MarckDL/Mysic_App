import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/api_failure.dart';
import 'package:mysic/features/connected_library/application/music_mode_controller.dart';
import 'package:mysic/features/connected_library/data/music_mode_client.dart';
import 'package:mysic/features/connected_library/domain/music_mode.dart';

import 'support/ytm_test_client.dart';

MusicConnection _linked(String generation) => MusicConnection(
  status: MusicLinkStatus.linked,
  provider: 'youtubeOAuth',
  personalization: 'verified',
  accounts: const [],
  account: const MusicAccount('a', 'Cuenta', false),
  generation: generation,
  libraryId: 'library-a',
  capabilities: const {'playlists', 'liked', 'history'},
);

/// Un servidor que tarda en responder y un cliente con una conexión guardada.
class _Slow extends MusicModeClient {
  _Slow(this.remembered) : super(ytm: ytmTestClient(), ytmAccount: () => null);

  final MusicConnection? remembered;
  final server = Completer<MusicConnection>();

  @override
  Future<MusicConnection?> rememberedConnection() async => remembered;

  @override
  Future<MusicConnection> connection({bool recheckMusic = false}) =>
      server.future;
}

void main() {
  (MusicModeController, _Slow, List<int>) mount(MusicConnection? remembered) {
    final client = _Slow(remembered);
    final cleared = <int>[];
    final controller = MusicModeController(
      client,
      () => true,
      () async => cleared.add(1),
    );
    addTearDown(controller.dispose);
    return (controller, client, cleared);
  }

  test(
    'la conexión guardada se muestra antes de que responda el servidor',
    () async {
      final (controller, client, cleared) = mount(_linked('g-1'));
      final refreshing = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      // Aún sin respuesta: ya hay conexión y la música se muestra.
      expect(controller.connection?.generation, 'g-1');
      expect(controller.wantsMusic, isTrue);
      expect(controller.busy, isTrue);

      client.server.complete(_linked('g-1'));
      await refreshing;
      // La misma conexión confirmada no reinicia nada.
      expect(controller.connection?.generation, 'g-1');
      expect(controller.isCurrent('g-1'), isTrue);
      expect(cleared, isEmpty);
    },
  );

  test(
    'si el servidor responde otra conexión, sustituye a la guardada',
    () async {
      final (controller, client, cleared) = mount(_linked('g-1'));
      final refreshing = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      client.server.complete(_linked('g-2'));
      await refreshing;
      expect(controller.connection?.generation, 'g-2');
      expect(controller.isCurrent('g-1'), isFalse);
      // El cambio de conexión limpia la reproducción, como siempre.
      expect(cleared, hasLength(1));
    },
  );

  test('sin conexión guardada se espera al servidor', () async {
    final (controller, client, _) = mount(null);
    final refreshing = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(controller.connection, isNull);
    client.server.complete(_linked('g-1'));
    await refreshing;
    expect(controller.connection?.generation, 'g-1');
  });

  test('si el servidor falla, la conexión guardada se conserva', () async {
    final (controller, client, _) = mount(_linked('g-1'));
    final refreshing = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    client.server.completeError(const ApiFailure('Sin red'));
    await refreshing;
    expect(controller.connection?.generation, 'g-1');
    expect(controller.failed, isTrue);
  });
}
