import 'dart:async';

import 'package:flutter/foundation.dart';

import '../storage/app_storage.dart';
import 'network_monitor.dart';
import 'sync_service.dart';

/// Sincronización automática del POS.
///
/// Disparadores:
///
/// 1. Al iniciar la aplicación.
/// 2. Cuando la conexión vuelve a estar disponible.
/// 3. Cada 5 minutos.
///
/// La sincronización real continúa centralizada en SyncService.syncManual().
class AutomaticSyncService {
  AutomaticSyncService._internal();

  static final AutomaticSyncService _instance =
      AutomaticSyncService._internal();

  factory AutomaticSyncService() => _instance;

  static const Duration _syncInterval = Duration(minutes: 5);

  final NetworkMonitor _networkMonitor = NetworkMonitor();
  final SyncService _syncService = SyncService();

  Timer? _timer;

  VoidCallback? _networkListener;

  bool _started = false;
  bool _syncInProgress = false;

  // ============================================================
  // INICIAR
  // ============================================================

  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;

    _networkListener = () {
      unawaited(_onNetworkStatusChanged());
    };

    _networkMonitor.addListener(_networkListener!);

    _timer = Timer.periodic(
      _syncInterval,
      (_) {
        unawaited(_syncIfPossible());
      },
    );

    // Intento inicial.
    //
    // Si todavía no hay conexión, simplemente se omite.
    // Cuando NetworkMonitor detecte online, volverá a intentarlo.
    await _syncIfPossible();
  }

  // ============================================================
  // CAMBIO DE RED
  // ============================================================

  Future<void> _onNetworkStatusChanged() async {
    if (!_started) {
      return;
    }

    if (!_networkMonitor.isOnline) {
      return;
    }

    await _syncIfPossible();
  }

  // ============================================================
  // INTENTAR SINCRONIZAR
  // ============================================================

  Future<void> _syncIfPossible() async {
    if (!_started) {
      return;
    }

    if (_syncInProgress) {
      return;
    }

    if (!_networkMonitor.isOnline) {
      return;
    }

    final storage = AppStorage();

    if (await storage.isOfflineSession()) {
      print(
        'ℹ️ Sync automática omitida: '
        'sesión offline.',
      );

      return;
    }

    final companyId =
        await storage.getEmpresaId() ?? 0;

    final userId =
        await storage.getUserId() ?? 0;

    if (companyId <= 0 || userId <= 0) {
      print(
        'ℹ️ Sync automática omitida: '
        'no existe una sesión válida.',
      );

      return;
    }

    _syncInProgress = true;

    try {
      print(
        '🔄 Iniciando sincronización automática...',
      );

      final result = await _syncService.syncManual(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      print(
        '✅ Sincronización automática finalizada: '
        'total=${result.total} '
        'synced=${result.synced} '
        'failed=${result.failed} '
        'skipped=${result.skipped}',
      );

      if (result.failed > 0) {
        print(
          '⚠️ Sincronización automática terminó '
          'con ${result.failed} operación(es) fallida(s).',
        );
      }
    } catch (e) {
      print(
        '❌ Error en sincronización automática: $e',
      );
    } finally {
      _syncInProgress = false;
    }
  }

  // ============================================================
  // DETENER
  // ============================================================

  Future<void> stop() async {
    if (!_started) {
      return;
    }

    _started = false;

    _timer?.cancel();
    _timer = null;

    final listener = _networkListener;

    if (listener != null) {
      _networkMonitor.removeListener(listener);
      _networkListener = null;
    }

    print(
      '⏹️ Sincronización automática detenida.',
    );
  }

  // ============================================================
  // ESTADO
  // ============================================================

  bool get isRunning => _started;

  bool get isSyncing => _syncInProgress;
}