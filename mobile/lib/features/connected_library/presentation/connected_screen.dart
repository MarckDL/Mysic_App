import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../application/connected_controller.dart';
import '../application/connected_host.dart';
import '../domain/music_mode.dart';
import 'music_mode_host.dart';
import 'desktop_music_access.dart';

class ConnectedTile extends StatelessWidget {
  const ConnectedTile({super.key, this.account = false});
  final bool account;
  @override
  Widget build(BuildContext context) {
    final model = ConnectedScope.of(context);
    if (model == null) return const SizedBox.shrink();
    final connection = model.connection;
    final initial = connection?.status == 'unlinked' && model.pending == null;
    return ListTile(
      leading: const Icon(Icons.subscriptions_outlined),
      title: Text(
        account
            ? 'Canal de YouTube'
            : initial
            ? 'Vincular YouTube'
            : 'Biblioteca de YouTube',
      ),
      subtitle: Text(
        model.pending != null
            ? 'Vinculación en curso'
            : connection?.linked == true
            ? 'Playlists de ${connection!.channel!.title}'
            : account
            ? 'Vincula tu canal para abrir sus playlists'
            : 'Playlists de tu canal',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {
        context.push('/library/youtube');
        if (initial && !account && !model.busy) unawaited(model.start());
      },
    );
  }
}

class ConnectedScreen extends StatelessWidget {
  const ConnectedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final model = ConnectedScope.of(context);
    final connection = model?.connection;
    final listing =
        model != null && connection?.linked == true && model.pending == null;
    final music = MusicModeScope.of(context);
    final access = music?.connection;
    final direct = access?.isDirect == true;
    final hasPersonalHome = access?.capabilities.contains('home') == true;
    final needsSelection = direct && music?.wantsMusic == false;
    final offerPersonalLibrary =
        needsSelection &&
        access?.status == MusicLinkStatus.linked &&
        !hasPersonalHome &&
        music?.supportsDesktop == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Canal de YouTube'),
        actions: [
          if (listing)
            PopupMenuButton<String>(
              tooltip: 'Opciones del vínculo',
              enabled: !model.busy,
              onSelected: (value) async {
                if (value == 'change') {
                  await model.start(restart: true);
                  return;
                }
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('¿Desvincular YouTube?'),
                    content: Text(
                      'Se retirará el acceso al canal ${connection?.channel?.title ?? ''}. Tu sesión de Mysic seguirá abierta.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Desvincular'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && model.alive) {
                  if (context.mounted) {
                    final music = MusicModeScope.of(context);
                    if (music?.connection?.isDesktop != true) {
                      music?.useLocal(disconnecting: true);
                    }
                  }
                  await model.unlink();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'change',
                  child: Text('Cambiar cuenta de YouTube'),
                ),
                PopupMenuItem(
                  value: 'unlink',
                  child: Text('Desvincular YouTube'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: model == null
            ? const Center(child: Text('El piloto está desactivado.'))
            : listing
            ? ListView(
                children: [
                  if (offerPersonalLibrary)
                    DesktopMusicAccess(music!, forHome: true),
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(connection!.channel!.title),
                    subtitle: Text(
                      music?.busy == true
                          ? 'Comprobando acceso musical…'
                          : direct && hasPersonalHome
                          ? 'Inicio personal de YouTube Music disponible'
                          : direct && access?.personalization == 'partialMusic'
                          ? 'Biblioteca musical parcial'
                          : direct && access?.channelOnly == true
                          ? 'Solo biblioteca del canal'
                          : 'Canal vinculado',
                    ),
                    trailing: TextButton(
                      onPressed: music?.busy == true
                          ? null
                          : () async {
                              if (music != null && access?.isDesktop == true) {
                                await switchMusicSource(
                                  context,
                                  music,
                                  toDesktop: false,
                                );
                                return;
                              }
                              if (music != null && needsSelection) {
                                await music.useLinkedAccount();
                                if (!context.mounted || !music.wantsMusic) {
                                  return;
                                }
                              }
                              if (context.mounted) context.go('/library');
                            },
                      child: Text(
                        access?.isDesktop == true ||
                                (needsSelection && !hasPersonalHome)
                            ? 'Usar este canal'
                            : 'Biblioteca',
                      ),
                    ),
                  ),
                  if (music != null && !offerPersonalLibrary)
                    DesktopMusicAccess(music),
                ],
              )
            : _LinkPanel(model: model),
      ),
    );
  }
}

class _LinkPanel extends StatelessWidget {
  const _LinkPanel({required this.model});
  final ConnectedController model;
  @override
  Widget build(BuildContext context) {
    final pending = model.pending, channel = model.candidate;
    final connection = model.connection;
    final busy = model.busy;
    final revoked = connection?.status == 'revocation_pending';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (busy)
          const LinearProgressIndicator(semanticsLabel: 'Consultando YouTube'),
        if (model.needsUnlinkRetry) ...[
          const Text('Desvinculando YouTube'),
          if (!busy)
            FilledButton(
              onPressed: model.unlink,
              child: const Text('Reintentar desvinculación'),
            ),
        ] else if (channel != null) ...[
          Text(
            model.replaceRequired
                ? '¿Reemplazar el canal vinculado?'
                : 'Confirma tu canal',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (model.replaceRequired && connection?.channel != null)
            Text('Canal actual: ${connection!.channel!.title}'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(channel.title),
          ),
          FilledButton(
            onPressed: busy ? null : model.confirmCandidate,
            child: Text(
              model.replaceRequired
                  ? 'Reemplazar por este canal'
                  : 'Confirmar este canal',
            ),
          ),
        ] else if (pending != null) ...[
          Text(
            'Esperando autorización',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Elige tu cuenta y canal en Google. Si ya terminaste, comprueba el resultado aquí.',
          ),
          FilledButton(
            onPressed: busy ? null : () => model.sync(),
            child: const Text('Comprobar vinculación'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => model.start(restart: pending.id != null),
            child: const Text('Volver a abrir Google'),
          ),
        ] else if (connection != null && !revoked) ...[
          Text(
            connection.status == 'reauthorization_required'
                ? 'Vuelve a autorizar tu canal'
                : 'Vincular un canal de YouTube',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Elige el canal cuyas playlists quieres consultar.'),
          FilledButton.icon(
            onPressed: busy ? null : () => model.start(),
            icon: const Icon(Icons.open_in_new),
            label: Text(
              model.forceConsent ? 'Volver a dar permiso' : 'Vincular YouTube',
            ),
          ),
        ] else if (revoked)
          const Text(
            'El acceso desde Mysic ya se retiró. La revocación en Google está pendiente.',
          ),
        if (pending != null && !model.needsUnlinkRetry)
          TextButton(
            onPressed: busy ? null : model.cancel,
            child: const Text('Cancelar vinculación'),
          ),
        if (model.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(model.message!, semanticsLabel: model.message),
          ),
        if (!busy &&
            !model.needsUnlinkRetry &&
            pending == null &&
            (connection == null || revoked || model.message != null))
          OutlinedButton(
            onPressed: () => model.sync(),
            child: const Text('Reintentar'),
          ),
      ],
    );
  }
}
