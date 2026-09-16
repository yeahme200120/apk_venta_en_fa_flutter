import 'dart:async';

import 'package:flutter/foundation.dart';

import '../storage/app_storage.dart';

// ============================================================
// ESTADO DE LICENCIA
// ============================================================

enum LicenseStatus {
  /// No hay snapshot. Bloquea hasta login online.
  sinSnapshot,

  /// Licencia permanente activa.
  permanente,

  /// Dentro de vigencia (fecha_fin >= ahora).
  vigente,

  /// Hasta 3 días después de fecha_fin.
  enGracia,

  /// Más de 3 días después de fecha_fin. Bloqueo total.
  bloqueada,
}

class LicenseState {
  const LicenseState({
    required this.status,
    required this.tipo,
    required this.fechaFin,
    required this.diasRestantes,
    required this.diasVencidos,
    required this.mensaje,
  });

  final LicenseStatus status;
  final String tipo;
  final DateTime? fechaFin;
  final int? diasRestantes;
  final int diasVencidos;
  final String mensaje;

  bool get permiteOperar =>
      status == LicenseStatus.permanente ||
      status == LicenseStatus.vigente ||
      status == LicenseStatus.enGracia;

  bool get esBloqueoTotal =>
      status == LicenseStatus.bloqueada ||
      status == LicenseStatus.sinSnapshot;

  bool get debeAvisarGracia => status == LicenseStatus.enGracia;

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'tipo': tipo,
    'fecha_fin': fechaFin?.toIso8601String(),
    'dias_restantes': diasRestantes,
    'dias_vencidos': diasVencidos,
    'mensaje': mensaje,
  };
}

// ============================================================
// SERVICIO
// ============================================================

class LicenseService {
  LicenseService._internal();

  static final LicenseService _instance = LicenseService._internal();

  factory LicenseService() => _instance;

  static const int _diasGracia = 3;

  final StreamController<LicenseState> _stateController =
      StreamController<LicenseState>.broadcast();

  Stream<LicenseState> get changes => _stateController.stream;

  LicenseState? _cached;

  LicenseState? get cached => _cached;

  // ============================================================
  // CONSULTA
  // ============================================================

  Future<LicenseState> evaluate() async {
    final storage = AppStorage();

    final snapshot = await storage.getLicenseSnapshot();

    // Sin snapshot → bloqueo total.
    if (snapshot == null || snapshot.isEmpty) {
      return _emit(
        const LicenseState(
          status: LicenseStatus.sinSnapshot,
          tipo: '',
          fechaFin: null,
          diasRestantes: null,
          diasVencidos: 0,
          mensaje: 'No hay licencia validada. Inicia sesión con Internet.',
        ),
      );
    }

    final tipo = (snapshot['licencia_tipo'] ?? '').toString().toLowerCase();

    // CORREGIDO: fechaFinRaw ahora es String no-nullable (?? '').
    // Esto elimina:
    //   - el warning unnecessary_null_comparison
    //   - el error de compilación "receiver can be null" en .trim()
    final String fechaFinRaw =
        snapshot['licencia_fecha_fin']?.toString() ?? '';

    final activa = snapshot['licencia_activa'] == true;
    final serverCheckedAtRaw = snapshot['server_checked_at']?.toString();

    if (!activa) {
      return _emit(
        LicenseState(
          status: LicenseStatus.bloqueada,
          tipo: tipo,
          // CORREGIDO: fechaFinRaw ya no es nullable, se quitó el ?? ''.
          fechaFin: DateTime.tryParse(fechaFinRaw),
          diasRestantes: 0,
          diasVencidos: 0,
          mensaje: 'La licencia está inactiva. Contacta a tu proveedor.',
        ),
      );
    }

    if (tipo == 'permanente') {
      return _emit(
        LicenseState(
          status: LicenseStatus.permanente,
          tipo: tipo,
          fechaFin: null,
          diasRestantes: null,
          diasVencidos: 0,
          mensaje: 'Licencia permanente activa.',
        ),
      );
    }

    // CORREGIDO: fechaFinRaw es String no-nullable → solo .isEmpty.
    if (fechaFinRaw.trim().isEmpty) {
      return _emit(
        LicenseState(
          status: LicenseStatus.bloqueada,
          tipo: tipo,
          fechaFin: null,
          diasRestantes: 0,
          diasVencidos: 0,
          mensaje: 'La licencia no tiene fecha de fin. Contacta a soporte.',
        ),
      );
    }

    final fechaFin = DateTime.tryParse(fechaFinRaw);

    if (fechaFin == null) {
      return _emit(
        LicenseState(
          status: LicenseStatus.bloqueada,
          tipo: tipo,
          fechaFin: null,
          diasRestantes: 0,
          diasVencidos: 0,
          mensaje: 'Fecha de licencia inválida.',
        ),
      );
    }

    final serverCheckedAt = DateTime.tryParse(serverCheckedAtRaw ?? '');
    final ahoraLocal = DateTime.now();

    DateTime ahoraEfectivo;

    if (serverCheckedAt != null && ahoraLocal.isAfter(serverCheckedAt)) {
      ahoraEfectivo = ahoraLocal;
    } else {
      ahoraEfectivo = serverCheckedAt ?? ahoraLocal;
    }

    final finDia = DateTime(
      fechaFin.year,
      fechaFin.month,
      fechaFin.day,
      23,
      59,
      59,
    );

    final hoy = DateTime(
      ahoraEfectivo.year,
      ahoraEfectivo.month,
      ahoraEfectivo.day,
    );

    final diff = finDia.difference(hoy).inDays;

    if (diff >= 0) {
      return _emit(
        LicenseState(
          status: LicenseStatus.vigente,
          tipo: tipo,
          fechaFin: fechaFin,
          diasRestantes: diff,
          diasVencidos: 0,
          mensaje: diff == 0
              ? 'La licencia vence hoy.'
              : 'Licencia vigente. Vence en $diff día(s).',
        ),
      );
    }

    final diasVencidos = diff.abs();

    if (diasVencidos <= _diasGracia) {
      return _emit(
        LicenseState(
          status: LicenseStatus.enGracia,
          tipo: tipo,
          fechaFin: fechaFin,
          diasRestantes: 0,
          diasVencidos: diasVencidos,
          mensaje: diasVencidos == 1
              ? 'Licencia vencida hace 1 día. '
                    'Regulariza antes de que se bloquee.'
              : 'Licencia vencida hace $diasVencidos días. '
                    'Regulariza antes de que se bloquee.',
        ),
      );
    }

    return _emit(
      LicenseState(
        status: LicenseStatus.bloqueada,
        tipo: tipo,
        fechaFin: fechaFin,
        diasRestantes: 0,
        diasVencidos: diasVencidos,
        mensaje:
            'Licencia vencida hace $diasVencidos días. '
            'Inicia sesión con Internet para reactivar.',
      ),
    );
  }

  Future<LicenseState> refresh() => evaluate();

  Future<void> clear() async {
    _cached = null;
    await AppStorage().clearLicenseSnapshot();
  }

  LicenseState _emit(LicenseState state) {
    _cached = state;

    if (!_stateController.isClosed) {
      _stateController.add(state);
    }

    return state;
  }

  @visibleForTesting
  void dispose() {
    _stateController.close();
  }
}