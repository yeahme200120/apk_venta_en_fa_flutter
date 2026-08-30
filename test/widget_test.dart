// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:punto_venta_flutter/core/services/auth_service.dart';
import 'package:punto_venta_flutter/main.dart';
import 'package:punto_venta_flutter/vistas/splash/splash_screen.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('La app inicia con el material app', (WidgetTester tester) async {
    await tester.pumpWidget(const PuntoVentaApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(SplashScreen), findsOneWidget);
  });

  test('las cuentas offline de prueba inician sesión sin internet', () async {
    final authService = AuthService();

    final response = await authService.login(
      identifier: '1000000003',
      password: 'yesy2001',
    );

    expect(response['user']['id'], 3);
    expect(response['user']['username'], 'Yesenia López');
    expect(await authService.hasSession(), isTrue);
  });
}
