import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

enum AppConnectionStatus { online, offline, syncing, limited }

class NetworkMonitor extends ChangeNotifier {
  NetworkMonitor._internal();

  static final NetworkMonitor _instance = NetworkMonitor._internal();

  factory NetworkMonitor() => _instance;

  final Connectivity _connectivity = Connectivity();

  AppConnectionStatus _status = AppConnectionStatus.online;
  Timer? _debounce;

  AppConnectionStatus get status => _status;

  bool get isOnline => _status == AppConnectionStatus.online;

  Future<void> initialize() async {
    _connectivity.onConnectivityChanged.listen((_) async {
      await _updateStatus();
    });

    await _updateStatus();
  }

  Future<void> _updateStatus() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    final hasTransport = connectivityResult.any(
      (result) => result != ConnectivityResult.none,
    );

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!hasTransport) {
        _status = AppConnectionStatus.offline;
      } else {
        _status = AppConnectionStatus.online;
      }
      notifyListeners();
    });
  }

  Future<void> markSyncing() async {
    _status = AppConnectionStatus.syncing;
    notifyListeners();
  }

  Future<void> markOnline() async {
    _status = AppConnectionStatus.online;
    notifyListeners();
  }
}
