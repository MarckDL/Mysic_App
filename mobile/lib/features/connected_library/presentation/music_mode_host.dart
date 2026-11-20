import 'dart:async';

import 'package:flutter/material.dart';

import '../application/music_mode_controller.dart';

class MusicModeScope extends InheritedNotifier<MusicModeController> {
  const MusicModeScope({
    super.key,
    required MusicModeController controller,
    required super.child,
  }) : super(notifier: controller);

  static MusicModeController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MusicModeScope>()?.notifier;
}

class MusicModeHost extends StatefulWidget {
  const MusicModeHost({
    super.key,
    required this.controller,
    required this.child,
  });
  final MusicModeController controller;
  final Widget child;

  @override
  State<MusicModeHost> createState() => _MusicModeHostState();
}

class _MusicModeHostState extends State<MusicModeHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.controller.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MusicModeScope(controller: widget.controller, child: widget.child);
}
