class PaymentEntry {
  const PaymentEntry({required this.method, required this.amount});

  final String method;
  final double amount;

  PaymentEntry copyWith({String? method, double? amount}) {
    return PaymentEntry(
      method: method ?? this.method,
      amount: amount ?? this.amount,
    );
  }
}

class PaymentBreakdown {
  const PaymentBreakdown({
    required this.total,
    required this.payments,
  });

  final double total;
  final List<PaymentEntry> payments;

  double get totalCollected => payments.fold(0.0, (sum, item) => sum + item.amount);

  double get cashAmount => payments
      .where((item) => item.method.toLowerCase() == 'efectivo')
      .fold(0.0, (sum, item) => sum + item.amount);

  double get backendCashAmount => cashAmount;

  double get change => cashAmount > total ? cashAmount - total : 0.0;

  double get excess => totalCollected > total ? totalCollected - total : 0.0;

  double get shortfall => totalCollected < total ? total - totalCollected : 0.0;

  String get statusLabel {
    if (excess > 0) return 'Cobro adicional';
    if (shortfall > 0) return 'Falta por cobrar';
    if (totalCollected == total) return 'Cobro exacto';
    return 'Cobro parcial';
  }

  String get summary {
    if (excess > 0) {
      return 'Se recibió más de lo debido; el cambio se calcula sobre el efectivo.';
    }
    if (shortfall > 0) {
      return 'Falta por cobrar ${shortfall.toStringAsFixed(2)}.';
    }
    return 'El cobro coincide con el total.';
  }
}
