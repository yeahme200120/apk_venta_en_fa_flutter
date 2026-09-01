import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../storage/app_storage.dart';

/// Servicio encargado de ejecutar sincronizaciones automáticas
/// cuando existe conexión a Internet.
///
/// Características:
/// - Detecta cambios de conectividad.
/// - Ejecuta la sincronización cuando vuelve Internet.
/// - Reintenta automáticamente cuando una sincronización falla.
/// - Evita tener varios timers simultáneos.
/// - Puede detenerse correctamente mediante [dispose].
/// - No contiene lógica de UI.
/// - No modifica directamente el estado de las ventas.
class AutomaticSyncService {
  AutomaticSyncService({
    Duration? retryBase,
  }) : _retryBase = retryBase ?? const Duration(seconds: 5);

  final Duration _retryBase;

  final Connectivity _connectivity = Connectivity();

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Timer? _timer;

  int _attempt = 0;

  bool _started = false;
  bool _disposed = false;
  bool _syncRunning = false;

  /// Stream que informa si existe conexión.
  Stream<bool> get onConnectivityChanged =>
      _connectionController.stream;

  /// Inicia el monitoreo de conectividad y la sincronización automática.
  Future<void> start({
    required Future<void> Function() syncAction,
  }) async {
    if (_disposed) return;

    // Evita registrar el listener varias veces.
    if (_started) return;

    _started = true;

    try {
      final result = await _connectivity.checkConnectivity();

      if (_disposed) return;

      final connected = _isConnected(result);

      _connectionController.add(connected);

      if (connected) {
        _scheduleRetry(
          syncAction,
          isFirstRun: true,
        );
      }

      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen(
        (result) {
          if (_disposed) return;

          final connected = _isConnected(result);

          _connectionController.add(connected);

          if (connected) {
            _attempt = 0;

            _scheduleRetry(
              syncAction,
              isFirstRun: false,
            );
          } else {
            _timer?.cancel();
            _timer = null;
          }
        },
        onError: (_) {
          // No dejamos que un error del stream rompa
          // el servicio completo.
        },
      );
    } catch (_) {
      if (_disposed) return;

      _connectionController.add(false);
    }
  }

  bool _isConnected(List<ConnectivityResult> result) {
    return result.any(
      (item) => item != ConnectivityResult.none,
    );
  }

  void _scheduleRetry(
    Future<void> Function() syncAction, {
    required bool isFirstRun,
  }) {
    if (_disposed) return;

    // Nunca dejamos dos timers ejecutándose.
    _timer?.cancel();
    _timer = null;

    final int multiplier = _attempt <= 0 ? 1 : _attempt + 1;

    final Duration delay = Duration(
      seconds: _retryBase.inSeconds * multiplier,
    );

    _timer = Timer(delay, () async {
      _timer = null;

      if (_disposed) return;

      await _executeSync(syncAction);
    });
  }

  Future<void> _executeSync(
    Future<void> Function() syncAction,
  ) async {
    if (_disposed) return;

    // Evita sincronizaciones simultáneas.
    if (_syncRunning) return;

    _syncRunning = true;

    try {
      final token = await AppStorage().getToken();

      if (_disposed) return;

      if ((token ?? '').trim().isEmpty) {
        _attempt = 0;
        return;
      }

      await syncAction();

      if (_disposed) return;

      // Sincronización exitosa:
      // reiniciamos el contador de reintentos.
      _attempt = 0;
    } catch (_) {
      if (_disposed) return;

      _attempt++;

      // Evita que el contador crezca indefinidamente.
      if (_attempt > 10) {
        _attempt = 10;
      }

      _scheduleRetry(
        syncAction,
        isFirstRun: false,
      );
    } finally {
      _syncRunning = false;
    }
  }

  /// Detiene completamente el servicio.
  ///
  /// Es importante llamarlo desde State.dispose() para evitar:
  /// - timers activos después de destruir la pantalla;
  /// - listeners de connectivity acumulados;
  /// - actualizaciones después de dispose;
  /// - múltiples sincronizaciones duplicadas.
  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    _timer?.cancel();
    _timer = null;

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    if (!_connectionController.isClosed) {
      await _connectionController.close();
    }

    _started = false;
    _syncRunning = false;
  }
}
