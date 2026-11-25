import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/api_failure.dart';
import 'package:mysic/features/ytm/data/ytm_client.dart';
import 'package:mysic/features/ytm/data/ytm_session.dart';

/// Responde 401 a la cookie vieja y 200 a la que se le indique.
class _Server implements HttpClientAdapter {
  _Server({required this.accepts});

  final String accepts;
  final cookies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final cookie = options.headers['Cookie'] as String? ?? '';
    cookies.add(cookie);
    return ResponseBody.fromString(
      cookie == accepts ? '{}' : '',
      cookie == accepts ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _channel = 'UCaaaaaaaaaaaaaaaaaaaaaa';
const _old = 'SAPISID=cuenta1; __Secure-1PSIDTS=viejo';
const _new = 'SAPISID=cuenta1; __Secure-1PSIDTS=nuevo';

void main() {
  setUp(YtmClient.forgetRenewals);

  YtmClient client(_Server server, Future<YtmSession?> Function() renew) =>
      YtmClient(
        const YtmSession(_old),
        dio: Dio()..httpClientAdapter = server,
        renew: renew,
      );

  test(
    'con la cookie rechazada, renueva y repite la petición una vez',
    () async {
      final server = _Server(accepts: _new);
      var renewals = 0;
      final ytm = client(server, () async {
        renewals++;
        return const YtmSession(_new);
      });

      await ytm.follow(_channel, followed: true);

      expect(renewals, 1);
      expect(server.cookies, [
        _old,
        _new,
      ], reason: 'la segunda ya va con la nueva');
      expect(ytm.session.cookie, _new);
    },
  );

  test('las siguientes peticiones ya usan la cookie nueva', () async {
    final server = _Server(accepts: _new);
    final ytm = client(server, () async => const YtmSession(_new));
    await ytm.follow(_channel, followed: true);
    server.cookies.clear();

    await ytm.follow(_channel, followed: false);

    expect(server.cookies, [_new]);
  });

  test('si no hay nada más fresco, pide iniciar sesión de nuevo', () async {
    final server = _Server(accepts: 'otra');
    final ytm = client(server, () async => null);
    await expectLater(
      ytm.follow(_channel, followed: true),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'MUSIC_ACCESS_DENIED'),
      ),
    );
    expect(server.cookies, [_old], reason: 'sin renovar no se repite');
  });

  test('una cookie de otra cuenta no sustituye a la actual', () async {
    final server = _Server(accepts: 'SAPISID=otra');
    final ytm = client(
      server,
      () async => const YtmSession('SAPISID=otra; __Secure-1PSIDTS=x'),
    );
    await expectLater(
      ytm.follow(_channel, followed: true),
      throwsA(isA<ApiFailure>()),
    );
    expect(ytm.session.cookie, _old, reason: 'no se cambia de cuenta');
  });

  test('no se pide la renovación más de una vez cada 5 minutos', () async {
    var now = DateTime(2026, 1, 1, 12);
    var renewals = 0;
    final server = _Server(accepts: 'nada');
    final ytm = YtmClient(
      const YtmSession(_old),
      dio: Dio()..httpClientAdapter = server,
      clock: () => now,
      renew: () async {
        renewals++;
        return null;
      },
    );

    await expectLater(
      ytm.follow(_channel, followed: true),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      ytm.follow(_channel, followed: true),
      throwsA(isA<ApiFailure>()),
    );
    expect(renewals, 1, reason: 'una ráfaga de rechazos es un solo problema');

    now = now.add(const Duration(minutes: 6));
    await expectLater(
      ytm.follow(_channel, followed: true),
      throwsA(isA<ApiFailure>()),
    );
    expect(renewals, 2);
  });

  test('otro cliente aprovecha la renovación sin pedirla otra vez', () async {
    final server = _Server(accepts: _new);
    var renewals = 0;
    Future<YtmSession?> renew() async {
      renewals++;
      return const YtmSession(_new);
    }

    await client(server, renew).follow(_channel, followed: true);
    server.cookies.clear();
    // Un segundo cliente que aún trae la cookie vieja.
    await client(server, renew).follow(_channel, followed: true);

    expect(renewals, 1);
    expect(server.cookies, [_old, _new]);
  });
}
