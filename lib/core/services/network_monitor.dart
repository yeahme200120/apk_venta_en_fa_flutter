import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

enum AppConnectionStatus { online, offline, syncing, limited }

class NetworkMonitor extends ChangeNotifier {
  NetworkMonitor._internal();
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  factory NetworkMonitor() => _instance;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _debounce;
  AppConnectionStatus _status = AppConnectionStatus.offline;
  bool _initialized = false;

  AppConnectionStatus get status => _status;
  bool get isOnline => _status == AppConnectionStatus.online;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _subscription = _connectivity.onConnectivityChanged.listen((_) => _updateStatus());
    await _updateStatus();
  }

  Future<void> _updateStatus() async {
    final result = await _connectivity.checkConnectivity();
    final hasTransport = result.any((r) => r != ConnectivityResult.none);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _status = hasTransport ? AppConnectionStatus.online : AppConnectionStatus.offline;
      notifyListeners();
    });
  }

  Future<void> markSyncing() async { _status = AppConnectionStatus.syncing; notifyListeners(); }
  Future<void> markOnline() async { _status = AppConnectionStatus.online; notifyListeners(); }

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
