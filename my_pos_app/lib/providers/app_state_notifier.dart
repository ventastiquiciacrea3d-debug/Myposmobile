// lib/providers/app_state_notifier.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/woocommerce_service.dart';
import '../services/storage_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_manager.dart';
import '../services/cache_warming_service.dart';
import '../services/ultra_optimized_polling_service.dart';
import 'app_state.dart';
import 'shared_providers.dart';

part 'app_state_notifier.g.dart';

/// ✓ FASE 2 RIVERPOD: AppState Notifier
@riverpod
class AppStateNotifier extends _$AppStateNotifier with WidgetsBindingObserver {
  WooCommerceService? _wooCommerceService;
  StorageService? _storageService;
  ConnectivityService? _connectivityService;
  SyncManager? _syncManager;
  CacheWarmingService? _cacheWarmingService;
  UltraOptimizedPollingService? _pollingService;

  Timer? _notificationTimer;
  Timer? _errorTimer;
  StreamSubscription? _connectivitySubscription;

  /// 🟢 NUEVO: Getter público para acceder al polling service desde otros widgets
  UltraOptimizedPollingService? get pollingService => _pollingService;

  @override
  AppState build() {
    debugPrint("[AppStateNotifier] build() called - Returning initial state");

    ref.onDispose(() {
      debugPrint("[AppStateNotifier] Disposing");
      WidgetsBinding.instance.removeObserver(this);
      _connectivitySubscription?.cancel();
      _syncManager?.removeListener(_onSyncStateChanged);
      _notificationTimer?.cancel();
      _errorTimer?.cancel();
    });

    // ✓ SOLUCIÓN DEADLOCK RIVERPOD: NO inicializar automáticamente en build()
    // El build() SOLO retorna el estado inicial de forma síncrona
    // La inicialización asíncrona se hace EXPLÍCITAMENTE desde SplashScreen
    // mediante initialize() después de que el provider esté listo

    return AppState.initial();
  }

  /// ✓ NUEVA API PÚBLICA: Inicialización explícita
  /// Debe ser llamada UNA SOLA VEZ desde SplashScreen después de que
  /// coreServicesProvider haya completado y el provider esté listo
  Future<void> initialize() async {
    // Prevenir múltiples inicializaciones
    if (_wooCommerceService != null) {
      debugPrint("[AppStateNotifier] initialize() - Ya inicializado, ignorando");
      return;
    }

    await _init();
  }

  void _onSyncStateChanged() {
    if (_syncManager == null) return;
    state = state.copyWith(
      isSyncing: _syncManager!.isSyncing,
      currentSyncTask: _syncManager!.currentTask,
      syncError: _syncManager!.lastError,
      syncProgressMessage: _syncManager!.currentProgressMessage,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    super.didChangeAppLifecycleState(lifecycleState);

    if (lifecycleState == AppLifecycleState.resumed) {
      debugPrint("[AppStateNotifier] App resumed. Re-checking connectivity.");
      _connectivityService?.checkConnectivity();
    }
  }

  Future<void> _init() async {
    try {
      debugPrint("[AppStateNotifier] _init() - Loading service instances from GetIt...");

      // ✓ PASO 1: Cargar servicios (SÍNCRONO - muy rápido)
      _wooCommerceService = ref.read(wooCommerceServiceProvider);
      _storageService = ref.read(storageServiceProvider);
      _connectivityService = ref.read(connectivityServiceProvider);
      _syncManager = ref.read(syncManagerProvider);
      _cacheWarmingService = ref.read(cacheWarmingServiceProvider);
      _pollingService = ref.read(ultraOptimizedPollingServiceProvider);

      debugPrint("[AppStateNotifier] _init() - Services loaded");

      // ✓ PASO 2: Operaciones ligeras (UI observers, listeners)
      WidgetsBinding.instance.addObserver(this);
      _syncManager!.addListener(_onSyncStateChanged);

      final connectionMode = _storageService!.getConnectionMode();
      state = state.copyWith(connectionMode: connectionMode);

      debugPrint("[AppStateNotifier] _init() - Observers registered");

      // ✓ PASO 3: Dar tiempo al UI thread para respirar
      await Future.delayed(const Duration(milliseconds: 50));

      // ✓ PASO 4: Operaciones async NO-BLOQUEANTES
      // Usar Future.microtask para no bloquear el event loop
      await Future.microtask(() async {
        // Cargar configuración de forma no-bloqueante
        await _loadAppConfigurationNonBlocking();
      });

      debugPrint("[AppStateNotifier] _init() - Configuration loaded");

      // ✓ PASO 5: Dar otro respiro al UI
      await Future.delayed(const Duration(milliseconds: 50));

      // ✓ PASO 6: Setup conectividad de forma no-bloqueante
      await Future.microtask(() async {
        // Listen to connectivity changes
        _connectivitySubscription = _connectivityService!.onConnectivityChanged.listen(
          (isConnected) => _handleConnectivityChange(isConnected),
          onError: (_) => _handleConnectivityChange(false),
        );

        // Initial connectivity check
        final bool isConnected = await _connectivityService!.checkConnectivity();
        _handleConnectivityChange(isConnected, isInitialCheck: true);
      });

      debugPrint("[AppStateNotifier] _init() - Connectivity configured");

      // ✅ PASO 6.5: VERIFICAR CONEXIÓN A LA API
      await Future.microtask(() async {
        if (state.isAppConfigured && state.isOnline) {
          debugPrint("[AppStateNotifier] _init() - Verificando conexión a la API...");

          final bool isApiConnected = await _wooCommerceService!.verifyApiConnection();

          if (isApiConnected) {
            debugPrint("[AppStateNotifier] _init() - ✅ API conectada correctamente");
            state = state.copyWith(
              isApiConnected: true,
              apiConnectionError: null,
            );
          } else {
            debugPrint("[AppStateNotifier] _init() - ❌ No se pudo conectar a la API");
            state = state.copyWith(
              isApiConnected: false,
              apiConnectionError: "No se pudo conectar a la API de WooCommerce",
            );
          }
        } else {
          debugPrint("[AppStateNotifier] _init() - Verificación de API omitida (app no configurada o sin conexión)");
          state = state.copyWith(
            isApiConnected: false,
            apiConnectionError: state.isAppConfigured ? "Sin conexión a internet" : "App no configurada",
          );
        }
      });

      debugPrint("[AppStateNotifier] _init() - API verification completed");

      // ✓ PASO 7: Cache warming si app está online y configurada
      if (state.isAppConfigured && state.isOnline && state.isApiConnected) {
        // NO usar await - ejecutar en background sin bloquear
        debugPrint("[AppStateNotifier] _init() - Triggering cache warming...");
        _cacheWarmingService!.warmCache(strategy: CacheWarmingStrategy.moderate).then((_) {
          debugPrint("[AppStateNotifier] Cache warming completed in background");
        }).catchError((e) {
          debugPrint("[AppStateNotifier] Cache warming failed (non-critical): $e");
        });
      }

      // ✓ PASO 8: Trigger sync si es necesario (ASYNC, no esperar)
      if (state.isAppConfigured && state.isOnline && state.isApiConnected) {
        // NO usar await - dejar que se ejecute en background
        _syncManager!.triggerSync();
      }

      debugPrint("[AppStateNotifier] _init() - Initialization complete");
    } catch (e, s) {
      debugPrint("[AppStateNotifier] CRITICAL ERROR during _init: $e\nStacktrace: $s");
      setAppError("Error Crítico al Inicializar: ${e.toString()}", durationSeconds: 15);

      state = state.copyWith(isAppConfigured: false, isFullyInitialized: false);
    } finally {
      // ✓ CRÍTICO: Marcar como completamente inicializado
      state = state.copyWith(isLoading: false, isFullyInitialized: true);
      debugPrint("[AppStateNotifier] _init() - State marked as fully initialized");
    }
  }

  void _handleConnectivityChange(bool isConnected, {bool isInitialCheck = false}) {
    final newStatus = isConnected ? ConnectionStatus.online : ConnectionStatus.offline;

    if (state.connectionStatus != newStatus) {
      state = state.copyWith(connectionStatus: newStatus);

      debugPrint("[AppStateNotifier] Connectivity changed to: $newStatus");

      if (newStatus == ConnectionStatus.online && state.isAppConfigured && _syncManager != null) {
        _syncManager!.triggerSync();
      } else if (newStatus == ConnectionStatus.offline && !isInitialCheck) {
        setAppNotification(
          "Sin conexión. Algunas funciones pueden estar limitadas.",
          durationSeconds: 5,
        );
      }
    }
  }

  // ========== CONFIGURATION METHODS ==========

  Future<void> loadAppConfiguration() async {
    if (_storageService == null || _wooCommerceService == null) {
      debugPrint("[AppStateNotifier] Services not initialized yet, skipping loadAppConfiguration");
      return;
    }

    clearError();

    final connectionMode = _storageService!.getConnectionMode();

    await _wooCommerceService!.initializeDioClient();
    final isConfigured = _wooCommerceService!.isServiceInitialized;

    state = state.copyWith(
      connectionMode: connectionMode,
      isAppConfigured: isConfigured,
    );

    debugPrint("[AppStateNotifier] App configuration loaded - Configured: $isConfigured, Mode: $connectionMode");
  }

  /// ✓ NUEVA: Versión no-bloqueante de loadAppConfiguration
  Future<void> _loadAppConfigurationNonBlocking() async {
    if (_storageService == null || _wooCommerceService == null) {
      debugPrint("[AppStateNotifier] Services not initialized yet");
      return;
    }

    clearError();

    final connectionMode = _storageService!.getConnectionMode();

    // Inicializar Dio client de forma no-bloqueante
    await _wooCommerceService!.initializeDioClient();

    // Pequeño delay para no bloquear
    await Future.delayed(const Duration(milliseconds: 10));

    final isConfigured = _wooCommerceService!.isServiceInitialized;

    state = state.copyWith(
      connectionMode: connectionMode,
      isAppConfigured: isConfigured,
    );

    debugPrint("[AppStateNotifier] Config loaded - Configured: $isConfigured");
  }

  Future<void> setConnectionMode(String mode) async {
    if (_storageService == null) {
      debugPrint("[AppStateNotifier] StorageService not initialized yet");
      return;
    }

    if (mode == state.connectionMode) return;

    state = state.copyWith(connectionMode: mode);
    await _storageService!.saveConnectionMode(mode);

    debugPrint("[AppStateNotifier] Connection mode changed to '$mode'. Re-initializing services.");
    await loadAppConfiguration();
  }

  Future<bool> configureApp({
    required String apiUrl,
    String? consumerKey,
    String? consumerSecret,
    String? myPosApiKey,
  }) async {
    if (_storageService == null || _wooCommerceService == null) {
      setAppError("Servicios no inicializados. Por favor reinicia la aplicación.");
      return false;
    }

    setAppNotification("Probando conexión y guardando...");

    try {
      await _storageService!.saveApiUrl(apiUrl.trim());
      await _storageService!.saveConsumerKey(consumerKey?.trim() ?? '');
      await _storageService!.saveConsumerSecret(consumerSecret?.trim() ?? '');
      await _storageService!.saveMyPosApiKey(myPosApiKey?.trim() ?? '');

      await _wooCommerceService!.testConnection(
        apiUrl: apiUrl,
        consumerKey: consumerKey ?? '',
        consumerSecret: consumerSecret ?? '',
        myPosApiKey: myPosApiKey ?? '',
      );

      await loadAppConfiguration();

      if (state.isAppConfigured) {
        setAppNotification("Configuración guardada exitosamente.");
        return true;
      } else {
        setAppError("La configuración se guardó, pero la conexión falló. Verifica la URL y las claves.");
        return false;
      }
    } on ApiException catch (e) {
      setAppError("Error API al conectar: ${e.message}");
      state = state.copyWith(isAppConfigured: false, isFullyInitialized: false);
      return false;
    } catch (e) {
      setAppError('Error inesperado al configurar: ${e.toString()}');
      state = state.copyWith(isAppConfigured: false, isFullyInitialized: false);
      return false;
    }
  }

  // ========== NOTIFICATION METHODS ==========

  void setAppNotification(String? message, {int durationSeconds = 4}) {
    _notificationTimer?.cancel();

    if (message != null) {
      clearError();
    }

    state = state.copyWith(appNotification: message);

    if (message != null) {
      _notificationTimer = Timer(Duration(seconds: durationSeconds), () {
        if (state.appNotification == message) {
          state = state.copyWith(appNotification: null);
        }
      });
    }
  }

  void setAppError(String? message, {int durationSeconds = 7}) {
    _errorTimer?.cancel();

    if (message != null) {
      clearNotification();
    }

    state = state.copyWith(appError: message);

    if (message != null) {
      _errorTimer = Timer(Duration(seconds: durationSeconds), () {
        if (state.appError == message) {
          state = state.copyWith(appError: null);
        }
      });
    }
  }

  void clearError() {
    if (state.appError != null) {
      _errorTimer?.cancel();
      state = state.copyWith(appError: null);
    }
  }

  void clearNotification() {
    if (state.appNotification != null) {
      _notificationTimer?.cancel();
      state = state.copyWith(appNotification: null);
    }
  }
}
