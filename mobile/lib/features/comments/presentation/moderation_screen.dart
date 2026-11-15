import 'package:flutter/material.dart';

import 'comment_feed_panel.dart';

class ModerationScreen extends StatelessWidget {
  const ModerationScreen({super.key, required this.canModerate});

  final bool canModerate;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Moderación de comentarios')),
    body: SafeArea(
      child: canModerate
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: const [CommentFeedPanel.moderation()],
            )
          : const Center(
              child: Text('No tienes permiso para moderar comentarios.'),
            ),
    ),
  );
}
