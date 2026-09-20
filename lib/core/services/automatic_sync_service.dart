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
  bool? _lastKnownOnlineState;

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

    _timer = Timer.periodic(_syncInterval, (_) {
      unawaited(_syncIfPossible());
    });

    // 🔑 FIX: ya no se dispara `_syncIfPossible()` de inmediato.
    //
    // Motivo:
    //   • `NetworkMonitor.initialize()` corre en paralelo (ver main.dart)
    //     y su primer cambio de estado dispara `_onNetworkStatusChanged()`,
    //     que a su vez llama a `_syncIfPossible()`. Resultado: dos
    //     sincronizaciones en el arranque.
    //
    //   • Además, en el arranque puede no haber sesión o token aún,
    //     y `_syncIfPossible()` fallaría o generaría ruido.
    //
    // Se hace un intento diferido tras 3 segundos para dar tiempo a que
    // `NetworkMonitor` se estabilice y a que el login (si aplica) termine.
    Timer(const Duration(seconds: 3), () {
      if (_started) {
        unawaited(_syncIfPossible());
      }
    });
  }

  // ============================================================
  // CAMBIO DE RED
  // ============================================================

  Future<void> _onNetworkStatusChanged() async {
    if (!_started) {
      return;
    }

    final isOnlineNow = _networkMonitor.isOnline;

    // Ignorar el primer cambio (es el de la inicialización).
    if (_lastKnownOnlineState == null) {
      _lastKnownOnlineState = isOnlineNow;
      return;
    }

    // Ignorar si no cambió.
    if (_lastKnownOnlineState == isOnlineNow) {
      return;
    }

    _lastKnownOnlineState = isOnlineNow;

    if (!isOnlineNow) {
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
      debugPrint('ℹ️ Sync automática omitida: sesión offline.');
      return;
    }

    final companyId = await storage.getEmpresaId() ?? 0;
    final userId = await storage.getUserId() ?? 0;

    if (companyId <= 0 || userId <= 0) {
      debugPrint('ℹ️ Sync automática omitida: no existe una sesión válida.');
      return;
    }

    // 🔑 FIX: exigir token online. Si no hay token, no sincronizamos.
    //
    // Motivo:
    //   • La auto-sync no debe intentar sincronizar si el usuario
    //     no ha hecho login online todavía.
    //   • Sin token, todas las llamadas al backend devolverían 401
    //     y llenarían el log de ruido innecesario.
    final token = await storage.getToken();

    if (token == null || token.trim().isEmpty) {
      debugPrint('ℹ️ Sync automática omitida: sin token online.');
      return;
    }

    _syncInProgress = true;

    try {
      debugPrint('🔄 Iniciando sincronización automática...');

      final result = await _syncService.syncManual(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      debugPrint(
        '✅ Sincronización automática finalizada: '
        'total=${result.total} '
        'synced=${result.synced} '
        'failed=${result.failed} '
        'skipped=${result.skipped}',
      );

      if (result.failed > 0) {
        debugPrint(
          '⚠️ Sincronización automática terminó '
          'con ${result.failed} operación(es) fallida(s).',
        );
      }
    } catch (e) {
      debugPrint('❌ Error en sincronización automática: $e');
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

    debugPrint('⏹️ Sincronización automática detenida.');
  }

  // ============================================================
  // ESTADO
  // ============================================================

  bool get isRunning => _started;

  bool get isSyncing => _syncInProgress;
}
