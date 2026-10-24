import 'package:flutter_test/flutter_test.dart';
import 'package:mysic/app/mysic_app.dart';

void main() {
  testWidgets('muestra la pantalla inicial sin una sesión ficticia', (
    tester,
  ) async {
    await tester.pumpWidget(const MysicApp());
    expect(find.text('Mysic'), findsOneWidget);
    expect(find.textContaining('iniciar sesión con Google'), findsOneWidget);
  });
}
