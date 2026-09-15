import '../database/local_db.dart';

/// Fachada offline-first para caja.
///
/// Todo se escribe primero en SQLite y se encola en sync_queue.
/// No bloquea la UI por red. El SyncService sube después.
class CashService {
  final LocalDb _db = LocalDb();

  // ============================================================
  // APERTURA / REAPERTURA
  // ============================================================
  //
  // Offline-first:
  //
  //   1. Si NO existe caja hoy → la crea local y encola apertura.
  //   2. Si existe caja abierta → devuelve error claro.
  //   3. Si existe caja cerrada hoy → la reabre localmente
  //      (mismo registro, deja nota de reapertura en
  //      notas_apertura) y encola reapertura al backend.
  //
  // El backend, con la nueva lógica de CajaController::abrir,
  // responde 201 (nueva) o 200 (reapertura) con mensaje claro.
  // ============================================================

  Future<Map<String, dynamic>> openCash({
    required double montoApertura,
    String? notas,
  }) {
    return _db.openCashRegisterLocal(
      montoApertura: montoApertura,
      notas: notas,
    );
  }

  // ============================================================
  // CIERRE
  // ============================================================

  Future<Map<String, dynamic>> closeCash({
    required int cashRegisterId,
    required double montoDeclarado,
    String? notas,
  }) {
    return _db.closeCashRegisterLocal(
      cashRegisterId: cashRegisterId,
      montoDeclarado: montoDeclarado,
      notas: notas,
    );
  }

  // ============================================================
  // MOVIMIENTOS
  // ============================================================

  Future<Map<String, dynamic>> addMovement({
    required int cashRegisterId,
    required String tipo,
    required String concepto,
    required double monto,
    String? referencia,
    String? notas,
    String? formaPago,
  }) {
    return _db.addCashMovementLocal(
      cashRegisterId: cashRegisterId,
      tipo: tipo,
      concepto: concepto,
      monto: monto,
      referencia: referencia,
      notas: notas,
      formaPago: formaPago,
    );
  }

  // ============================================================
  // CONSULTAS
  // ============================================================

  /// Devuelve la caja abierta hoy o `null` si no hay ninguna.
  Future<Map<String, dynamic>?> getCurrentCash() {
    return _db.getCurrentCashRegisterLocal();
  }

  /// Resumen de movimientos de una caja.
  Future<Map<String, dynamic>> getSummary(int cashRegisterId) {
    return _db.getCashSummaryLocal(
      cashRegisterId: cashRegisterId,
    );
  }

  /// Movimientos filtrados por caja, rango de fechas y tipo.
  Future<List<Map<String, dynamic>>> getMovements({
    int? cashRegisterId,
    DateTime? desde,
    DateTime? hasta,
    String? tipo,
  }) {
    return _db.getCashMovementsLocal(
      cashRegisterId: cashRegisterId,
      desde: desde,
      hasta: hasta,
      tipo: tipo,
    );
  }

  /// Historial de cajas (aperturas/cierres) en un rango opcional.
  Future<List<Map<String, dynamic>>> getHistory({
    DateTime? desde,
    DateTime? hasta,
  }) {
    return _db.getCashRegistersLocal(
      desde: desde,
      hasta: hasta,
    );
  }
}