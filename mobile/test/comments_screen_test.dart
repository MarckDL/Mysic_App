import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/core/network/authenticated_api_client.dart';
import 'package:mysic/features/authentication/application/auth_providers.dart';
import 'package:mysic/features/authentication/domain/auth_repository.dart';
import 'package:mysic/features/comments/application/comment_providers.dart';
import 'package:mysic/features/comments/domain/comments.dart';
import 'package:mysic/features/comments/presentation/comment_feed_panel.dart';
import 'package:mysic/features/comments/presentation/moderation_screen.dart';

const trackId = 'youtube:abcdefghijk';
const other = SongComment(
  id: 'other',
  authorName: 'Cuenta B',
  body: 'Ajeno',
  isMine: false,
);
const reported = SongComment(
  id: 'other',
  authorName: 'Cuenta B',
  body: 'Reportado',
  isMine: false,
  reasons: [ReportReason.spam],
);

class _Comments implements CommentRepository {
  String? published;
  ReportReason? reason;
  ModerationAction? action;
  Completer<void>? pending;
  bool disposed = false;
  bool conflict = false;
  String account = 'a';

  @override
  Future<CommentPage> list(String id, {String? cursor}) async {
    if (account != 'a') return const CommentPage([], null);
    if (cursor != null) return const CommentPage([other], null);
    return CommentPage([
      if (published case final body?)
        SongComment(
          id: 'mine',
          authorName: 'Cuenta A',
          body: body,
          isMine: true,
        ),
    ], 'second');
  }

  @override
  Future<CommentPage> queue({String? cursor}) async =>
      CommentPage(action == null ? [reported] : [], null);

  @override
  Future<void> publish(String id, String body) async {
    await pending?.future;
    if (disposed) throw StateError('Cliente cerrado durante publicación');
    published = body;
  }

  @override
  Future<void> edit(String id, String body) async => published = body;

  @override
  Future<void> remove(String id) async => published = null;

  @override
  Future<void> report(String id, ReportReason reason) async =>
      this.reason = reason;

  @override
  Future<void> resolve(String id, ModerationAction action) async {
    this.action = action;
    if (conflict) throw const ApiFailure('Conflicto', statusCode: 409);
  }
}

Widget _app(
  _Comments repository,
  Widget child, {
  Stream<AuthUser?>? sessions,
}) => ProviderScope(
  overrides: [
    authStateProvider.overrideWith(
      (ref) => sessions ?? Stream.value(const AuthUser(uid: 'a')),
    ),
    commentRepositoryProvider.overrideWith((ref) {
      ref.onDispose(() => repository.disposed = true);
      return repository;
    }),
  ],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets(
    'publica sin cerrar el cliente, edita, elimina y reporta otra página',
    (tester) async {
      final repository = _Comments()..pending = Completer<void>();
      await tester.pumpWidget(
        _app(
          repository,
          const Scaffold(body: CommentFeedPanel(trackId: trackId)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escribir comentario'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publicar'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe un comentario.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '  Primera opinión  ');
      await tester.tap(find.text('Publicar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.disposed, isFalse);
      expect(repository.published, isNull);
      repository.pending!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Primera opinión'), findsOneWidget);
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Opinión editada');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Opinión editada'), findsOneWidget);
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(find.text('Opinión editada'), findsNothing);

      await tester.tap(find.text('Cargar más'));
      await tester.pumpAndSettle();
      expect(find.text('Ajeno'), findsOneWidget);
      expect(find.text('Editar'), findsNothing);
      await tester.tap(find.text('Reportar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      expect(repository.reason, ReportReason.spam);
    },
  );

  testWidgets(
    'excluye cuentas comunes y refresca la cola después de un conflicto',
    (tester) async {
      final repository = _Comments()..conflict = true;
      await tester.pumpWidget(
        _app(repository, const ModerationScreen(canModerate: false)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No tienes permiso para moderar comentarios.'),
        findsOneWidget,
      );
      expect(find.text('Reportado'), findsNothing);

      await tester.pumpWidget(
        _app(repository, const ModerationScreen(canModerate: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Spam'), findsOneWidget);
      await tester.tap(find.text('Ocultar'));
      await tester.pumpAndSettle();
      expect(repository.action, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Ocultar'));
      await tester.pumpAndSettle();
      expect(repository.action, ModerationAction.hide);
      expect(
        find.text('Otra sesión ya resolvió estos reportes.'),
        findsOneWidget,
      );
      expect(find.text('No hay reportes pendientes.'), findsOneWidget);
    },
  );

  testWidgets('descarta comentarios y permisos al cambiar de cuenta', (
    tester,
  ) async {
    final repository = _Comments()..published = 'Solo editable desde A';
    final sessions = StreamController<AuthUser?>();
    addTearDown(sessions.close);
    await tester.pumpWidget(
      _app(
        repository,
        const Scaffold(body: CommentFeedPanel(trackId: trackId)),
        sessions: sessions.stream,
      ),
    );
    sessions.add(const AuthUser(uid: 'a'));
    await tester.pumpAndSettle();
    expect(find.text('Solo editable desde A'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);

    repository.account = 'b';
    sessions.add(const AuthUser(uid: 'b'));
    await tester.pumpAndSettle();
    expect(find.text('Solo editable desde A'), findsNothing);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Aún no hay comentarios.'), findsOneWidget);
  });
}
