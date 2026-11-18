import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../authentication/application/auth_providers.dart';
import '../data/connected_client.dart';
import '../data/link_platform.dart';
import 'connected_controller.dart';

final youtubePilotProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('YOUTUBE_LIBRARY_ENABLED'),
);
final connectedControllerProvider = Provider.autoDispose
    .family<ConnectedController, String>((ref, uid) {
      final api = AuthenticatedApiClient(
        ref.watch(authRepositoryProvider),
        baseUrl: ApiConfig.baseUrl,
        keepSessionOnForbidden: true,
        ownerUid: uid,
      );
      final controller = ConnectedController(
        uid,
        ConnectedClient(api, Uri.parse(ApiConfig.baseUrl)),
        LinkPlatform(),
      );
      ref.onDispose(() {
        controller.dispose();
        api.close();
      });
      return controller;
    });

class ConnectedScope extends InheritedNotifier<ConnectedController> {
  const ConnectedScope({
    super.key,
    required ConnectedController controller,
    required super.child,
  }) : super(notifier: controller);
  static ConnectedController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnectedScope>()?.notifier;
}

class ConnectedHost extends StatefulWidget {
  const ConnectedHost({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.child,
  });
  final ConnectedController controller;
  final VoidCallback onReturn;
  final Widget child;
  @override
  State<ConnectedHost> createState() => _ConnectedHostState();
}

class _ConnectedHostState extends State<ConnectedHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.platform.onReturn(_resume);
    _resume();
  }

  void _resume() => unawaited(
    widget.controller.sync(
      browser: true,
      onReturn: () {
        if (mounted) widget.onReturn();
      },
    ),
  );
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.platform.onReturn(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ConnectedScope(controller: widget.controller, child: widget.child);
}
