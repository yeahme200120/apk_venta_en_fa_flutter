import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:punto_venta_flutter/core/storage/app_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppStorage', () {
    test('persists session data and restores it', () async {
      SharedPreferences.setMockInitialValues({});

      final storage = AppStorage();

      await storage.clear();

      await storage.saveSession(
        token: 'abc123',
        userId: 42,
        empresaId: 7,
        userName: 'Ana',
        isLoggedIn: true,
      );

      expect(await storage.getToken(), 'abc123');
      expect(await storage.getUserId(), 42);
      expect(await storage.getEmpresaId(), 7);
      expect(await storage.getUserName(), 'Ana');
      expect(await storage.isLoggedIn(), isTrue);
    });
  });
}