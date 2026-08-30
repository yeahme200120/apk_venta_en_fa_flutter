import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:punto_venta_flutter/core/payments/payment_breakdown.dart';
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

  test('calcula cambio y el efectivo que realmente se envía al backend', () {
    final breakdown = PaymentBreakdown(
      total: 150,
      payments: const [
        PaymentEntry(method: 'Efectivo', amount: 200),
        PaymentEntry(method: 'Tarjeta', amount: 50),
      ],
    );

    expect(breakdown.totalCollected, 250);
    expect(breakdown.cashAmount, 200);
    expect(breakdown.change, 50);
    expect(breakdown.excess, 100);
    expect(breakdown.backendCashAmount, 200);
    expect(breakdown.statusLabel, 'Cobro adicional');
  });
}
