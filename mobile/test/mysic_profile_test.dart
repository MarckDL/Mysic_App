import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/authentication/domain/mysic_profile.dart';
import 'package:mysic/features/ytm/data/ytm_auth_repository.dart';
import 'package:mysic/features/ytm/data/ytm_client.dart';

void main() {
  test(
    'el perfil de una cuenta de YouTube Music se guarda y se vuelve a leer',
    () {
      // El identificador de la cuenta es un hash de 24 caracteres, no un UUID:
      // si fromJson lo rechaza, la app no puede abrir sin conexión con el perfil
      // guardado.
      final uid = YtmAuthRepository.uidFor(const YtmAccount(name: 'Ana'));
      expect(uid, hasLength(24));
      final profile = MysicProfile(
        id: uid,
        uid: uid,
        displayName: 'Ana',
        nickname: 'Anita',
      );
      final copy = MysicProfile.fromJson(profile.toJson());
      expect(copy.id, uid);
      expect(copy.uid, uid);
      expect(copy.displayName, 'Ana');
      expect(copy.nickname, 'Anita');
    },
  );

  test('sigue leyendo los perfiles con UUID del servidor antiguo', () {
    final copy = MysicProfile.fromJson({
      'id': '00000000-0000-4000-8000-000000000001',
      'uid': 'a',
      'displayName': 'Ana',
    });
    expect(copy.uid, 'a');
  });

  test('rechaza identificadores que no son ni UUID ni el de la cuenta', () {
    for (final bad in [
      '',
      'abc',
      'zzzzzzzzzzzzzzzzzzzzzzzz',
      '1' * 23,
      '1' * 25,
    ]) {
      expect(
        () => MysicProfile.fromJson({
          'id': bad,
          'uid': 'a',
          'displayName': 'Ana',
        }),
        throwsA(isA<AuthFailure>()),
        reason: 'id "$bad"',
      );
    }
  });
}
