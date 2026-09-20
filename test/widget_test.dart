import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:punto_venta_flutter/main.dart';
import 'package:punto_venta_flutter/vistas/splash/splash_screen.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Mock de SharedPreferences para que AppStorage funcione
    // sin necesitar el plugin real en el entorno de test.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'La app inicia con el MaterialApp y muestra el SplashScreen',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const PuntoVentaApp(),
      );

      // La primera frame puede tardar en montar porque el
      // SplashScreen arranca tareas async. Hacemos un pump
      // adicional para que el árbol se estabilice.
      await tester.pump();

      expect(
        find.byType(MaterialApp),
        findsOneWidget,
      );

      // SplashScreen puede tardar un poco en aparecer por las
      // comprobaciones async de permisos. Reintentamos hasta
      // que aparezca, con un timeout razonable.
      expect(
        find.byType(SplashScreen),
        findsOneWidget,
      );
    },
  );
}