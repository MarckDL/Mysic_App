import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/mysic_profile.dart';

/// El último perfil verificado, guardado en el almacenamiento privado de la
/// app para abrirla sin esperar al servidor. Solo sirve para pintar: cada
/// petición sigue llevando su token y el servidor decide.
class ProfileCache {
  const ProfileCache();

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}profile.json');
    } on Object {
      // Sin plugin (pruebas) no hay caché.
      return null;
    }
  }

  /// El perfil guardado de [uid], o null si no hay, es de otra cuenta o no se
  /// puede leer.
  Future<MysicProfile?> read(String uid) async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      final profile = MysicProfile.fromJson(data);
      return profile.uid == uid ? profile : null;
    } on Object {
      return null;
    }
  }

  Future<void> write(MysicProfile profile) async {
    try {
      final file = await _file();
      if (file == null) return;
      // Temporal y renombrado: nunca queda un perfil a medias.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(profile.toJson()), flush: true);
      await temp.rename(file.path);
    } on Object {
      // Sin caché la app solo abre más despacio.
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (file != null && await file.exists()) await file.delete();
    } on Object {
      // Un perfil que no se pudo borrar se descarta al leerlo con otra cuenta.
    }
  }
}
