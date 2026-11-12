import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/playback/domain/playback_source_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/device_playback');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Android acepta solamente HTTPS de googlevideo', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'clear') return null;
      expect(call.method, 'resolve');
      expect(call.arguments, {'sourceId': 'q0Xrs0nfJ0c'});
      return {'url': 'https://r1.googlevideo.com/videoplayback?id=test'};
    });
    final resolver = AndroidPlaybackSourceResolver(channel: channel);

    final source = await resolver.resolve('q0Xrs0nfJ0c', 'firebase-token');

    expect(source.uri.host, 'r1.googlevideo.com');
    expect(source.headers, isEmpty);
    await resolver.dispose();
  });

  test('Android rechaza destinos devueltos fuera del CDN permitido', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'resolve') {
        return {'url': 'https://example.com/audio.m4a'};
      }
      return null;
    });
    final resolver = AndroidPlaybackSourceResolver(channel: channel);

    await expectLater(
      resolver.resolve('q0Xrs0nfJ0c', 'firebase-token'),
      throwsStateError,
    );
    await resolver.dispose();
  });

  test('Android no invoca código nativo sin pista y sesión válidas', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    final resolver = AndroidPlaybackSourceResolver(channel: channel);

    await expectLater(resolver.resolve('invalido', 'token'), throwsStateError);
    await expectLater(resolver.resolve('q0Xrs0nfJ0c', ''), throwsStateError);
    expect(calls, 0);
    await resolver.dispose();
  });

  test(
    'Android calienta, cancela anticipación nativa y limpia memoria',
    () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return null;
      });
      final resolver = AndroidPlaybackSourceResolver(channel: channel);

      await resolver.warmUp();
      resolver.cancelPrefetch();
      await Future<void>.delayed(Duration.zero);
      await resolver.clear();
      await resolver.dispose();

      expect(methods, containsAll(['warmUp', 'cancelPrefetch', 'clear']));
    },
  );
}
