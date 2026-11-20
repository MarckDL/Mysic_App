import '../../../app/mysic_theme.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../playback/application/playback_providers.dart';
import '../../playback/application/track_playback_controller.dart';
import '../../connected_library/presentation/connected_screen.dart';
import '../../connected_library/presentation/music_mode_host.dart';
import '../../connected_library/presentation/music_mode_screen.dart';
import '../application/auth_providers.dart';
import '../domain/mysic_profile.dart';

class AccountAction extends StatelessWidget {
  const AccountAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Abrir cuenta',
    icon: const CircleAvatar(
      radius: 15,
      child: Icon(Icons.person_outline, size: 20),
    ),
    onPressed: () => context.push('/account'),
  );
}

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key, required this.profile});

  final MysicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authActionsProvider);
    final music = MusicModeScope.of(context);
    final localMode = music?.showMusic != true;
    final editedProfile = ref.watch(editedProfileProvider);
    final currentProfile = editedProfile?.firebaseUid == profile.firebaseUid
        ? editedProfile!
        : profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const MysicBrandMark(size: 48),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentProfile.preferredName,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (profile.email case final email?)
                            Text(
                              email,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(
                currentProfile.nickname == null
                    ? 'Agregar apodo'
                    : 'Editar apodo',
              ),
              onTap: () => showDialog<void>(
                context: context,
                useRootNavigator: false,
                barrierDismissible: false,
                builder: (context) => _NicknameDialog(profile: currentProfile),
              ),
            ),
            const MusicModeSettings(),
            if (localMode && music == null) const ConnectedTile(account: true),
            if (profile.canModerateComments)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Moderar comentarios'),
                onTap: () => context.push('/moderation/comments'),
              ),
            if (localMode &&
                !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.android)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Probar el reproductor'),
                onTap: () {
                  final controller = ref.read(trackPlaybackControllerProvider);
                  if (controller.queue.length == 100 &&
                      !controller.queue.any(
                        (track) =>
                            track.id == TrackPlaybackController.demoTrack.id,
                      )) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('La cola está llena.')),
                    );
                    return;
                  }
                  unawaited(
                    controller.playTrack(TrackPlaybackController.demoTrack),
                  );
                  context.push('/player');
                },
              ),
            if (localMode && kDebugMode) ...[
              ListTile(
                leading: const Icon(Icons.volume_up_outlined),
                title: const Text('Prueba de audio'),
                onTap: () => context.push('/audio-test'),
              ),
              ListTile(
                leading: const Icon(Icons.headphones),
                title: const Text('Probar audio de YouTube'),
                onTap: () => context.push('/youtube-audio-test'),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: action.isLoading
                    ? null
                    : () => ref.read(authActionsProvider.notifier).signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ),
            if (action.hasError)
              const Text('No se pudo cerrar la sesión. Inténtalo de nuevo.'),
          ],
        ),
      ),
    );
  }
}

class _NicknameDialog extends ConsumerStatefulWidget {
  const _NicknameDialog({required this.profile});

  final MysicProfile profile;

  @override
  ConsumerState<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends ConsumerState<_NicknameDialog> {
  late String _input = widget.profile.nickname ?? '';
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    final nickname = _input.trim();
    if (nickname.runes.length > 24) {
      setState(() => _error = 'Usa hasta 24 caracteres.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(editedProfileProvider.notifier)
          .updateNickname(
            widget.profile.firebaseUid,
            nickname.isEmpty ? null : nickname,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'No se pudo guardar el apodo. Inténtalo de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Tu apodo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Elige un apodo corto, de hasta 24 caracteres. Si lo dejas vacío, '
            'verás tu nombre de Google.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _input,
            enabled: !_saving,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onChanged: (value) => setState(() {
              _input = value;
              _error = null;
            }),
            onFieldSubmitted: (_) => _save(),
            decoration: InputDecoration(labelText: 'Apodo', errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    ),
  );
}
