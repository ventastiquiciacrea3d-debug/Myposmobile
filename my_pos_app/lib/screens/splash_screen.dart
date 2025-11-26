// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../providers/app_state_notifier.dart';
import '../providers/shared_providers.dart';
import '../config/routes.dart';
import '../locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ✓ FASE 2 RIVERPOD: Migrado a ConsumerStatefulWidget
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _navigationDone = false;
  bool _appStateInitialized = false; // ✓ Flag para prevenir múltiples llamadas a initialize()

  @override
  void initState() {
    super.initState();
    debugPrint("[SplashScreen] initState - App started instantly!");

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();

    // ✓ SOLUCIÓN DEADLOCK RIVERPOD: Secuencia de inicialización en dos fases
    // FASE 1: Esperar a que coreServicesProvider complete (GetIt listo)
    // FASE 2: Llamar explícitamente a appStateNotifier.initialize()
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Listen to coreServicesProvider to trigger phase 2
        ref.listenManual(coreServicesProvider, (previous, next) {
          _initializeAppStateIfReady();
        });

        // Listen to appStateNotifierProvider for navigation
        ref.listenManual(appStateNotifierProvider, (previous, next) {
          _checkNavigationReady();
        });

        _initializeAppStateIfReady(); // Check initial state
      }
    });
  }

  /// ✓ FASE 2: Inicializar AppStateNotifier solo cuando coreServices esté listo
  void _initializeAppStateIfReady() async {
    if (!mounted || _appStateInitialized) return;

    final coreServicesAsync = ref.read(coreServicesProvider);

    coreServicesAsync.whenData((_) async {
      // Core services ready, now run migration if needed
      _appStateInitialized = true;
      debugPrint("[SplashScreen] Core services ready.");

      // ✅ MIGRACIÓN OBJECTBOX: Ejecutar una sola vez
      await _runMigrationIfNeeded();

      debugPrint("[SplashScreen] Initializing AppStateNotifier...");

      try {
        await ref.read(appStateNotifierProvider.notifier).initialize();
        debugPrint("[SplashScreen] AppStateNotifier initialized successfully");
        if (mounted) {
          _checkNavigationReady();
        }
      } catch (e) {
        debugPrint("[SplashScreen] ERROR initializing AppStateNotifier: $e");
        // Navigate to settings on error
        if (mounted) {
          _navigationDone = true;
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              Navigator.of(context).pushReplacementNamed(Routes.settings);
            }
          });
        }
      }
    });
  }

  /// ✅ MIGRACIÓN OBJECTBOX: Ejecuta migraciones de Hive → ObjectBox una sola vez
  Future<void> _runMigrationIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final migrationService = createDataMigrationService();

      // === MIGRACIÓN 1: PRODUCTOS (ATRIBUTOS) ===
      final productMigrationCompleted = prefs.getBool('objectbox_products_migration_completed') ?? false;

      if (!productMigrationCompleted) {
        debugPrint("[SplashScreen] ========================================");
        debugPrint("[SplashScreen] Iniciando migración de PRODUCTOS Hive → ObjectBox");
        debugPrint("[SplashScreen] ========================================");

        final result = await migrationService.migrateAttributesHiveToObjectBox(
          deleteHiveDataAfter: false, // Seguro: no borra Hive
        );

        debugPrint("[SplashScreen] Resultado migración productos: $result");

        if (result.success || result.successCount > 0) {
          final verification = await migrationService.verifyMigration();
          debugPrint("[SplashScreen] Resultado verificación productos: $verification");

          if (verification.success) {
            await prefs.setBool('objectbox_products_migration_completed', true);
            debugPrint("[SplashScreen] ✅ Migración de PRODUCTOS completada y verificada");
          } else {
            debugPrint("[SplashScreen] ⚠️ Verificación de productos falló, se reintentará");
          }
        } else {
          debugPrint("[SplashScreen] ⚠️ Migración de productos falló, se reintentará");
        }
      } else {
        debugPrint("[SplashScreen] Migración de PRODUCTOS ya completada, skip");
      }

      // === MIGRACIÓN 2: ÓRDENES ===
      final ordersMigrationCompleted = prefs.getBool('objectbox_orders_migration_completed') ?? false;

      if (!ordersMigrationCompleted) {
        debugPrint("[SplashScreen] ========================================");
        debugPrint("[SplashScreen] Iniciando migración de ÓRDENES Hive → ObjectBox");
        debugPrint("[SplashScreen] ========================================");

        final result = await migrationService.migrateOrdersHiveToObjectBox(
          deleteHiveDataAfter: false, // Seguro: no borra Hive
        );

        debugPrint("[SplashScreen] Resultado migración órdenes: $result");

        if (result.success || result.successCount > 0 || result.totalProducts == 0) {
          // Marcar como completado si: éxito, migró alguna, o no hay órdenes
          await prefs.setBool('objectbox_orders_migration_completed', true);
          debugPrint("[SplashScreen] ✅ Migración de ÓRDENES completada");
        } else {
          debugPrint("[SplashScreen] ⚠️ Migración de órdenes falló, se reintentará");
        }
      } else {
        debugPrint("[SplashScreen] Migración de ÓRDENES ya completada, skip");
      }

      // === MIGRACIÓN 3: LABELS ===
      final labelsMigrationCompleted = prefs.getBool('objectbox_labels_migration_completed') ?? false;

      if (!labelsMigrationCompleted) {
        debugPrint("[SplashScreen] ========================================");
        debugPrint("[SplashScreen] Iniciando migración de LABELS Hive → ObjectBox");
        debugPrint("[SplashScreen] ========================================");

        final result = await migrationService.migrateLabelsHiveToObjectBox(
          deleteHiveDataAfter: false, // Seguro: no borra Hive
        );

        debugPrint("[SplashScreen] Resultado migración labels: $result");

        if (result.success || result.successCount > 0 || result.totalProducts == 0) {
          // Marcar como completado si: éxito, migró alguna, o no hay labels
          await prefs.setBool('objectbox_labels_migration_completed', true);
          debugPrint("[SplashScreen] ✅ Migración de LABELS completada");
        } else {
          debugPrint("[SplashScreen] ⚠️ Migración de labels falló, se reintentará");
        }
      } else {
        debugPrint("[SplashScreen] Migración de LABELS ya completada, skip");
      }

      // === MARCAR MIGRACIÓN GENERAL COMO COMPLETADA (LEGACY FLAG) ===
      if (productMigrationCompleted || ordersMigrationCompleted || labelsMigrationCompleted) {
        await prefs.setBool('objectbox_migration_completed', true);
      }

    } catch (e, stackTrace) {
      debugPrint("[SplashScreen] ❌ Error durante migración: $e");
      debugPrint("[SplashScreen] Stack trace: $stackTrace");
      // No marcar como completado, reintentar en próximo arranque
    }
  }

  /// ✓ OPTIMIZACIÓN CRÍTICA: Verifica que TODO esté listo antes de navegar
  void _checkNavigationReady() {
    if (!mounted || _navigationDone || !_appStateInitialized) return;

    final coreServicesAsync = ref.read(coreServicesProvider);
    final appState = ref.read(appStateNotifierProvider);

    // Navigate only when:
    // 1. Core services are initialized (coreServicesAsync is data, not loading/error)
    // 2. AppStateNotifier.initialize() ha sido llamado (_appStateInitialized == true)
    // 3. AppState is no longer loading
    coreServicesAsync.when(
      data: (_) {
        // Core services ready + AppState initialized, check if loading is complete
        if (!appState.isLoading && appState.isFullyInitialized) {
          _navigationDone = true;

          // Small delay for animation to finish
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              final route = appState.isAppConfigured ? Routes.scanner : Routes.settings;
              debugPrint("[SplashScreen] Navigation to $route (everything ready)");
              Navigator.of(context).pushReplacementNamed(route);
            }
          });
        }
      },
      loading: () {
        // Still initializing core services, do nothing
        debugPrint("[SplashScreen] Core services still loading...");
      },
      error: (error, stackTrace) {
        // Initialization error, navigate to settings for reconfiguration
        _navigationDone = true;
        debugPrint("[SplashScreen] ERROR during initialization: $error");
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed(Routes.settings);
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE53935), Color(0xFFC62828)],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5), ), ],
                ),
                child: const Center(
                  child: Text(
                    "POS",
                    style: TextStyle( fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFFE53935), ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "MY POS MOBILE BARCODE",
                style: TextStyle( fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Punto de Venta Móvil para WooCommerce",
                style: TextStyle( fontSize: 14, color: Colors.white70, ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              if (kDebugMode)
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final coreServicesAsync = ref.watch(coreServicesProvider);
                      final appState = ref.watch(appStateNotifierProvider);

                      return coreServicesAsync.when(
                        data: (_) {
                          return Text(
                            appState.isLoading
                                ? "Servicios listos, configurando app..."
                                : (appState.isAppConfigured ? "✓ Todo listo" : "✓ Servicios OK, requiere config"),
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          );
                        },
                        loading: () => const Text(
                          "Inicializando servicios core...",
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        error: (err, _) => Text(
                          "Error: ${err.toString()}",
                          style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                        ),
                      );
                    },
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}