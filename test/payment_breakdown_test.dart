import 'package:flutter_test/flutter_test.dart';
import 'package:punto_venta_flutter/core/payments/payment_breakdown.dart';

void main() {
  test('calcula cambio solo sobre el efectivo pendiente en pago mixto', () {
    const breakdown = PaymentBreakdown(
      total: 100,
      payments: [
        PaymentEntry(method: 'Tarjeta', amount: 30),
        PaymentEntry(method: 'Efectivo', amount: 100),
      ],
    );

    expect(breakdown.nonCashAmount, 30);
    expect(breakdown.change, 30);
  });

  test('no genera cambio cuando el efectivo no excede el saldo restante', () {
    const breakdown = PaymentBreakdown(
      total: 100,
      payments: [
        PaymentEntry(method: 'Transferencia', amount: 40),
        PaymentEntry(method: 'Efectivo', amount: 60),
      ],
    );

    expect(breakdown.change, 0);
    expect(breakdown.shortfall, 0);
  });
}
