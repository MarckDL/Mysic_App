import 'auth_repository.dart';

class MysicProfile {
  const MysicProfile({
    required this.id,
    required this.uid,
    required this.displayName,
    this.email,
    this.nickname,
    this.canModerateComments = false,
  });

  final String id;
  final String uid;
  final String displayName;
  final String? email;
  final String? nickname;

  String get preferredName => nickname ?? displayName;
  final bool canModerateComments;

  /// El mismo formato que entrega el servidor y lee [MysicProfile.fromJson].
  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': uid,
    'displayName': displayName,
    'email': email,
    'nickname': nickname,
    'canModerateComments': canModerateComments,
  };

  factory MysicProfile.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    // Los perfiles guardados antes del cambio de cuenta usaban 'firebaseUid'.
    final uid = data['uid'] ?? data['firebaseUid'];
    final name = data['displayName'];
    final email = data['email'];
    final nickname = data['nickname'];
    // Un UUID (perfiles del servidor antiguo) o el identificador de 24
    // caracteres hexadecimales que sale de la cuenta de YouTube Music. Sin
    // aceptar este último el perfil guardado nunca se leía y la app no podía
    // abrir sin conexión.
    if (id is! String ||
        !RegExp(
          r'^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{24})$',
        ).hasMatch(id) ||
        uid is! String ||
        uid.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        (email != null && email is! String) ||
        (nickname != null && (nickname is! String || nickname.isEmpty))) {
      throw const AuthFailure('No se pudo confirmar tu perfil.');
    }
    return MysicProfile(
      id: id,
      uid: uid,
      displayName: name,
      email: email as String?,
      nickname: nickname as String?,
      canModerateComments: data['canModerateComments'] == true,
    );
  }
}
