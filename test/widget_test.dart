import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:punto_venta_flutter/main.dart';
import 'package:punto_venta_flutter/vistas/splash/splash_screen.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'La app inicia con el MaterialApp y muestra el SplashScreen',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const PuntoVentaApp(),
      );

      expect(
        find.byType(MaterialApp),
        findsOneWidget,
      );

      expect(
        find.byType(SplashScreen),
        findsOneWidget,
      );
    },
  );
}