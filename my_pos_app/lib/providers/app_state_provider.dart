// lib/providers/app_state_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/woocommerce_service.dart';
import '../services/storage_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_manager.dart';
import 'order_provider.dart';
import 'label_provider.dart';
import '../config/constants.dart';
import '../locator.dart';

enum ConnectionStatus { online, offline }

class AppStateProvider extends ChangeNotifier with WidgetsBindingObserver {
  final WooCommerceService _wooCommerceService = getIt<WooCommerceService>();
  final StorageService _storageService = getIt<StorageService>();
  final ConnectivityService _connectivityService = getIt<ConnectivityService>();
  final SyncManager _syncManager = getIt<SyncManager>();
  final OrderProvider orderProvider;
  final LabelProvider labelProvider;

  String _connectionMode = 'plugin';
  ConnectionStatus _connectionStatus = ConnectionStatus.offline;
  bool _isAppConfigured = false;
  bool _isLoading = true;
  String? _appError;
  String? _appNotification;
  Timer? _notificationTimer;
  Timer? _errorTimer;
  StreamSubscription? _connectivitySubscription;
  bool _isDisposed = false;

  String get connectionMode => _connectionMode;
  ConnectionStatus get connectionStatus => _connectionStatus;
  bool get isAppConfigured => _isAppConfigured;
  bool get isLoading => _isLoading;
  bool get isSyncing => _syncManager.isSyncing;
  SyncTask get currentSyncTask => _syncManager.currentTask;
  String? get error => _appError ?? _syncManager.lastError;
  String? get notification => _appNotification ?? _syncManager.currentProgressMessage;
  bool get isDisposed => _isDisposed;

  AppStateProvider({
    required this.orderProvider,
    required this.labelProvider,
  }) {
    debugPrint("[AppStateProvider] Constructor called.");
    _syncManager.addListener(_onSyncStateChanged);
    _init();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _init() async {
    if (!_isLoading) {
      _isLoading = true;
      if (!_isDisposed) notifyListeners();
    }

    try {
      _connectionMode = _storageService.getConnectionMode();
      await loadAppConfiguration();

      _connectivitySubscription = _connectivityService.onConnectivityChanged.listen(
            (isConnected) => _handleConnectivityChange(isConnected),
        onError: (_) => _handleConnectivityChange(false),
      );

      final bool isConnected = await _connectivityService.checkConnectivity();
      _handleConnectivityChange(isConnected, isInitialCheck: true);

      if (_isAppConfigured && _connectionStatus == ConnectionStatus.online) {
        _syncManager.triggerSync();
      }
    } catch(e, s) {
      debugPrint("[AppStateProvider] CRITICAL ERROR during _init: $e\nStacktrace: $s");
      setAppError("Error Crítico al Inicializar: ${e.toString()}", durationSeconds: 15);
      _isAppConfigured = false;
    } finally {
      if (!_isDisposed && _isLoading) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _onSyncStateChanged() {
    if (_isDisposed) return;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isDisposed) return;

    if (state == AppLifecycleState.resumed) {
      debugPrint("[AppStateProvider] App resumed. Re-checking connectivity.");
      _connectivityService.checkConnectivity();
    }
  }

  void _handleConnectivityChange(bool isConnected, {bool isInitialCheck = false}) {
    if (_isDisposed) return;
    final newStatus = isConnected ? ConnectionStatus.online : ConnectionStatus.offline;
    if (_connectionStatus != newStatus) {
      _connectionStatus = newStatus;
      debugPrint("[AppStateProvider] Connectivity changed to: $newStatus");
      if (newStatus == ConnectionStatus.online && _isAppConfigured) {
        _syncManager.triggerSync();
      } else if (newStatus == ConnectionStatus.offline && !isInitialCheck) {
        setAppNotification("Sin conexión. Algunas funciones pueden estar limitadas.", durationSeconds: 5);
      }
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> loadAppConfiguration() async {
    clearError();
    _connectionMode = _storageService.getConnectionMode();

    await _wooCommerceService.initializeDioClient();
    _isAppConfigured = _wooCommerceService.isServiceInitialized;

    if (!_isDisposed) notifyListeners();
  }

  Future<void> setConnectionMode(String mode) async {
    if (_isDisposed || mode == _connectionMode) return;
    _connectionMode = mode;
    await _storageService.saveConnectionMode(mode);
    debugPrint("[AppStateProvider] Connection mode changed to '$_connectionMode'. Re-initializing services.");
    await loadAppConfiguration();
  }

  Future<bool> configureApp({
    required String apiUrl,
    String? consumerKey, // Ahora es opcional
    String? consumerSecret, // Ahora es opcional
    String? myPosApiKey, // Ahora es opcional
  }) async {
    setAppNotification("Probando conexión y guardando...");

    try {
      await _storageService.saveApiUrl(apiUrl.trim());
      await _storageService.saveConsumerKey(consumerKey?.trim() ?? '');
      await _storageService.saveConsumerSecret(consumerSecret?.trim() ?? '');
      await _storageService.saveMyPosApiKey(myPosApiKey?.trim() ?? '');

      await _wooCommerceService.testConnection(
        apiUrl: apiUrl,
        consumerKey: consumerKey ?? '',
        consumerSecret: consumerSecret ?? '',
        myPosApiKey: myPosApiKey ?? '',
      );

      await loadAppConfiguration();

      if (_isAppConfigured) {
        setAppNotification("Configuración guardada exitosamente.");
        return true;
      } else {
        setAppError("La configuración se guardó, pero la conexión falló. Verifica la URL y las claves.");
        return false;
      }
    } on ApiException catch (e) {
      setAppError("Error API al conectar: ${e.message}");
      _isAppConfigured = false;
      return false;
    } catch (e) {
      setAppError('Error inesperado al configurar: ${e.toString()}');
      _isAppConfigured = false;
      return false;
    }
  }

  void setAppNotification(String? message, {int durationSeconds = 4}) {
    if (_isDisposed) return;
    _notificationTimer?.cancel();
    _appNotification = message;
    if (message != null) clearError();
    notifyListeners();
    if (message != null) {
      _notificationTimer = Timer(Duration(seconds: durationSeconds), () {
        if (_appNotification == message) _appNotification = null;
        if (!_isDisposed) notifyListeners();
      });
    }
  }

  void setAppError(String? message, {int durationSeconds = 7}) {
    if (_isDisposed) return;
    _errorTimer?.cancel();
    _appError = message;
    if (message != null) clearNotification();
    notifyListeners();
    if (message != null) {
      _errorTimer = Timer(Duration(seconds: durationSeconds), () {
        if (_appError == message) _appError = null;
        if (!_isDisposed) notifyListeners();
      });
    }
  }

  void clearError() {
    if (_appError != null) {
      _appError = null;
      _errorTimer?.cancel();
      if (!_isDisposed) notifyListeners();
    }
  }

  void clearNotification() {
    if (_appNotification != null) {
      _appNotification = null;
      _notificationTimer?.cancel();
      if (!_isDisposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    debugPrint("[AppStateProvider] dispose() called.");
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _syncManager.removeListener(_onSyncStateChanged);
    _notificationTimer?.cancel();
    _errorTimer?.cancel();
    super.dispose();
  }
}