// lib/services/connectivity_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  late final Stream<bool> onConnectivityChanged;

  bool? _lastStatus;

  ConnectivityService() {
    onConnectivityChanged = _connectivityController.stream;
    _initialize();
  }

  Future<void> _initialize() async {
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result, forceNotify: true);
    debugPrint("[ConnectivityService] Initialized. Current status: ${_lastStatus == true ? 'Online' : 'Offline'}");
  }

  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    return _getStatusFromResult(result);
  }

  void _updateConnectionStatus(List<ConnectivityResult> result, {bool forceNotify = false}) {
    final newStatus = _getStatusFromResult(result);
    if (forceNotify || newStatus != _lastStatus) {
      if (!forceNotify) {
        debugPrint("[ConnectivityService] Connectivity status CHANGED to: ${newStatus ? 'Online' : 'Offline'}");
      }
      if (!_connectivityController.isClosed) {
        _connectivityController.add(newStatus);
      }
      _lastStatus = newStatus;
    }
  }

  bool _getStatusFromResult(List<ConnectivityResult> result) {
    return !result.contains(ConnectivityResult.none);
  }

  void dispose() {
    _connectivityController.close();
  }
}