import 'auth_repository.dart';

class MysicProfile {
  const MysicProfile(
      {required this.id,
      required this.firebaseUid,
      required this.displayName,
      this.email});

  final String id;
  final String firebaseUid;
  final String displayName;
  final String? email;

  factory MysicProfile.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final uid = data['firebaseUid'];
    final name = data['displayName'];
    final email = data['email'];
    if (id is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(id) ||
        uid is! String ||
        uid.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        (email != null && email is! String)) {
      throw const AuthFailure('No se pudo confirmar tu perfil.');
    }
    return MysicProfile(
        id: id, firebaseUid: uid, displayName: name, email: email as String?);
  }
}
