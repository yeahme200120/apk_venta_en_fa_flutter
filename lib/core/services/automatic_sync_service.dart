import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../storage/app_storage.dart';

class AutomaticSyncService {
  AutomaticSyncService({Duration? retryBase}) : _retryBase = retryBase ?? const Duration(seconds: 10);

  final Duration _retryBase;
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _timer;
  Future<void> Function()? _syncAction;
  bool _started = false;
  bool _disposed = false;
  bool _running = false;
  int _attempt = 0;

  Stream<bool> get onConnectivityChanged => _connectionController.stream;

  Future<void> start({required Future<void> Function() syncAction}) async {
    if (_disposed) return;
    _syncAction = syncAction;
    if (_started) return;
    _started = true;

    final result = await _connectivity.checkConnectivity();
    final connected = result.any((r) => r != ConnectivityResult.none);
    _emit(connected);
    if (connected) _schedule(const Duration(seconds: 2));

    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final isConnected = result.any((r) => r != ConnectivityResult.none);
      _emit(isConnected);
      if (isConnected) {
        _attempt = 0;
        _schedule(const Duration(seconds: 2));
      } else {
        _timer?.cancel();
      }
    });
  }

  void _emit(bool value) {
    if (!_connectionController.isClosed) _connectionController.add(value);
  }

  void _schedule(Duration delay) {
    if (_disposed || _syncAction == null) return;
    _timer?.cancel();
    _timer = Timer(delay, _execute);
  }

  Future<void> _execute() async {
    if (_disposed || _running || _syncAction == null) return;
    final token = await AppStorage().getToken();
    if (token == null || token.isEmpty || token == 'offline-session') return;

    _running = true;
    try {
      await _syncAction!();
      _attempt = 0;
      _schedule(_retryBase);
    } catch (_) {
      _attempt = (_attempt + 1).clamp(1, 10);
      final seconds = _retryBase.inSeconds * _attempt;
      _schedule(Duration(seconds: seconds));
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    await _subscription?.cancel();
    await _connectionController.close();
  }
}
