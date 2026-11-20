import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../application/music_mode_controller.dart';
import '../domain/music_mode.dart';

class DesktopMusicAccess extends StatelessWidget {
  const DesktopMusicAccess(this.controller, {this.forHome = false, super.key});
  final bool forHome;
  final MusicModeController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.supportsDesktop) return const SizedBox.shrink();
    final connection = controller.connection;
    final saved = controller.hasDesktopSession;
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
                : saved && connection?.isDesktop != true
                ? 'Usar la biblioteca de ${controller.desktopName}'
                : forHome
                ? 'Conectar mi Inicio de YouTube Music'
                : 'Vincular mi biblioteca de YouTube Music',
          ),
          subtitle: linked
              ? Text(connection!.account!.name)
              : saved
              ? null
              : Text(
                  forHome
                      ? 'Con tu cuenta de Mysic de escritorio'
                      : 'Con tu cuenta de Mysic de escritorio',
                ),
          trailing: linked ? null : const Icon(Icons.chevron_right),
          onTap: linked || controller.busy
              ? null
              : () async {
                  if (saved && connection?.isDesktop != true) {
                    await switchMusicSource(
                      context,
                      controller,
                      toDesktop: true,
                      destination: forHome ? '/' : '/library',
                    );
                    return;
                  }
                  final connected = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _DesktopLogin(controller),
                  );
                  controller.cancelDesktopLink();
                  if (connected == true && context.mounted) {
                    context.go(forHome ? '/' : '/library');
                  }
                },
        ),
        if (!forHome &&
            (connection?.isDesktop == true || controller.hasDesktopSession) &&
            !controller.busy)
          TextButton(
            onPressed: controller.disconnectDesktop,
            child: const Text('Desconectar escritorio de este teléfono'),
          ),
      ],
    );
  }
}

Future<void> switchMusicSource(
  BuildContext context,
  MusicModeController controller, {
  required bool toDesktop,
  String destination = '/library',
}) async {
  try {
    await controller.switchSource(toDesktop: toDesktop);
    if (context.mounted) context.go(destination);
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiFailure
                ? error.message
                : 'No se pudo cambiar de biblioteca. Vuelve a intentarlo.',
          ),
        ),
      );
    }
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
    if (!widget.controller.pendingDesktopLink &&
        (_email.text.trim().isEmpty || _password.text.isEmpty)) {
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
      if (widget.controller.pendingDesktopLink) {
        await widget.controller.finishDesktopLink();
      } else {
        await widget.controller.connectDesktop(
          _email.text,
          _password.text,
          remember: _remember,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        if (widget.controller.pendingDesktopLink) _password.clear();
        setState(() {
          _error = error is ApiFailure
              ? (error.code == 'DESKTOP_MUSIC_LINK' &&
                        widget.controller.pendingDesktopLink
                    ? 'La biblioteca personal sigue pendiente.'
                    : error.message)
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
            if (widget.controller.pendingDesktopLink) ...[
              const Icon(Icons.library_music_rounded, size: 36),
              const SizedBox(height: 12),
              const Text(
                'Abre Mysic de escritorio con esta misma cuenta y completa la vinculación de YouTube Music. Cuando veas tu Inicio personal, vuelve aquí.',
              ),
            ] else ...[
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
            ],
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Verificando el Inicio musical',
              ),
            if (_error != null && _error!.isNotEmpty)
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
          child: Text(
            _busy
                ? 'Comprobando…'
                : widget.controller.pendingDesktopLink
                ? 'Comprobar biblioteca'
                : 'Conectar',
          ),
        ),
      ],
    ),
  );
}
