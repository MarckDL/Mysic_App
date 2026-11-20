import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';

class DesktopMusicAccess extends StatelessWidget {
  const DesktopMusicAccess(this.controller, {super.key});
  final MusicModeController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.supportsDesktop) return const SizedBox.shrink();
    final connection = controller.connection;
    final linked =
        connection?.isDesktop == true &&
        connection?.status == MusicLinkStatus.linked;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.computer),
          title: Text(
            linked
                ? 'Biblioteca de Mysic de escritorio'
                : 'Conectar Mysic de escritorio',
          ),
          subtitle: Text(
            linked
                ? 'Cuenta de escritorio · ${connection!.account!.name}'
                : 'Usa los Me gusta, las playlists y el Inicio de tu cuenta de escritorio.',
          ),
          trailing: linked ? null : const Icon(Icons.chevron_right),
          onTap: linked || controller.busy
              ? null
              : () async {
                  final connected = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _DesktopLogin(controller),
                  );
                  if (connected == true && context.mounted) {
                    context.go('/library');
                  }
                },
        ),
        if ((connection?.isDesktop == true || controller.hasDesktopSession) &&
            !controller.busy)
          TextButton(
            onPressed: controller.disconnectDesktop,
            child: const Text('Desconectar escritorio de este teléfono'),
          ),
      ],
    );
  }
}

class _DesktopLogin extends StatefulWidget {
  const _DesktopLogin(this.controller);
  final MusicModeController controller;
  @override
  State<_DesktopLogin> createState() => _DesktopLoginState();
}

class _DesktopLoginState extends State<_DesktopLogin> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _remember = true, _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(
        () => _error = 'Escribe tu correo y contraseña de Mysic de escritorio.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.connectDesktop(
        _email.text,
        _password.text,
        remember: _remember,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiFailure
              ? error.message
              : 'No se pudo completar la conexión. Reintenta.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Conectar Mysic de escritorio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entra con el correo y la contraseña que usas en Mysic de escritorio. Se envían directamente a myslc.duckdns.org.',
            ),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Correo de Mysic'),
            ),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Contraseña de Mysic',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Recordar la sesión en este dispositivo'),
              value: _remember,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _remember = v == true),
            ),
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Verificando el Inicio musical',
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Comprobando…' : 'Conectar'),
        ),
      ],
    ),
  );
}
