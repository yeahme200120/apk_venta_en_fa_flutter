import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../network/api_client.dart';
import '../storage/app_storage.dart';

class AutomaticSyncService {
  AutomaticSyncService({
    ApiClient? apiClient,
    Duration? retryBase,
  }) : _retryBase = retryBase ?? const Duration(seconds: 5);

  final Duration _retryBase;
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  final Connectivity _connectivity = Connectivity();
  Timer? _timer;
  int _attempt = 0;

  Stream<bool> get onConnectivityChanged => _connectionController.stream;

  Future<void> start({
    required Future<void> Function() syncAction,
  }) async {
    final result = await _connectivity.checkConnectivity();
    _connectionController.add(result.any((item) => item != ConnectivityResult.none));

    if (result.any((item) => item != ConnectivityResult.none)) {
      _scheduleRetry(syncAction, isFirstRun: true);
    }

    _connectivity.onConnectivityChanged.listen((result) {
      final connected = result.any((item) => item != ConnectivityResult.none);
      _connectionController.add(connected);

      if (connected) {
        _scheduleRetry(syncAction, isFirstRun: false);
      }
    });
  }

  void _scheduleRetry(
    Future<void> Function() syncAction, {
    required bool isFirstRun,
  }) {
    if (!isFirstRun) {
      _timer?.cancel();
    }

    final delay = Duration(
      seconds: _retryBase.inSeconds * (_attempt == 0 ? 1 : _attempt + 1),
    );

    _timer = Timer(delay, () async {
      final token = await AppStorage().getToken();
      if ((token ?? '').isEmpty) return;

      try {
        await syncAction();
        _attempt = 0;
      } catch (_) {
        _attempt += 1;
        _scheduleRetry(syncAction, isFirstRun: false);
      }
    });
  }
}
