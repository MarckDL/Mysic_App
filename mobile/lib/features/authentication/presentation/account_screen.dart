import '../../../app/mysic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final editedProfile = ref.watch(editedProfileProvider);
    final currentProfile = editedProfile?.uid == profile.uid
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
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Ajustes'),
              subtitle: const Text('Apariencia, letras y almacenamiento'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings'),
            ),
            const MusicModeSettings(),
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
            widget.profile.uid,
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
            'verás el nombre de tu canal de YouTube Music.',
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
