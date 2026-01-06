// lib/screens/scanner_screen.dart
// ✅ VERSIÓN 2.0 - ARREGLO DEFINITIVO
// Problemas resueltos:
// 1. Cámara no reanuda después de agregar/cancelar producto
// 2. Múltiples diálogos abriéndose
// 3. Botón "Cerrar" no funcionaba

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/product.dart';
import '../providers/scanner_notifier.dart';
import '../providers/scanner_state.dart';
import '../providers/order_notifier.dart';
import '../providers/app_state_notifier.dart';
import '../providers/app_state.dart';
import '../providers/shared_providers.dart';
import '../widgets/app_header.dart';
import '../config/constants.dart';
import '../config/routes.dart';
import '../widgets/dial_floating_action_button.dart';
import '../widgets/custom_fab_location.dart';
import '../widgets/add_to_cart_dialog.dart';
import '../widgets/scanner_zoom_control.dart'; // ✅ NUEVO: Widget de control de zoom
import '../app.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> with WidgetsBindingObserver {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final currencyFormat = NumberFormat.currency(locale: 'es_CR', symbol: '₡');
  Timer? _searchDebounce;
  bool _hideImagesInSearch = false;
  String _currentSearchQueryForDebounce = '';
  int _currentBottomNavIndex = 0;
  bool _isCameraPausedManually = false;

  // ✅ MEJORA: Estado para control de zoom
  double _currentZoom = 0.0;
  bool _isFixedZoomEnabled = false;
  bool _showZoomControl = false; // Toggle para mostrar/ocultar control de zoom

  // ✅ ARREGLO v2.0: Control de diálogos simplificado y robusto
  bool _isDialogOpen = false;

  // ✅ ARREGLO v2.0: Cooldown para evitar escaneos duplicados
  DateTime? _lastScanTime;
  static const _scanCooldown = Duration(milliseconds: 1500);

  StreamSubscription? _rapidScanSubscription;
  StreamSubscription? _notificationSubscription;

  final ScrollController _searchResultsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _barcodeController.addListener(_onSearchTextChanged);
    _searchResultsScrollController.addListener(_onSearchResultsScroll);
    _barcodeFocusNode.addListener(_onFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appStateValue = ref.read(appStateNotifierProvider);
      final scannerNotifier = ref.read(scannerProvider.notifier);

      _setupRapidScanListeners(scannerNotifier);
      _loadSettingsAndInitScanner(appStateValue.isAppConfigured);

      MyPosApp.initializeBackgroundServicePostSplash();
    });
  }

  Future<void> _loadSettingsAndInitScanner(bool isAppConfigured) async {
    await _loadSearchSettings();
    await _loadZoomSettings(); // ✅ NUEVO: Cargar configuración de zoom
    if (mounted) {
      final scannerNotifier = ref.read(scannerProvider.notifier);
      if (isAppConfigured) {
        await scannerNotifier.startScanner();
      } else {
        await scannerNotifier.resetScanner(keepSearchResults: true);
      }
      if (mounted) setState(() => _currentBottomNavIndex = 0);
    }
  }

  // ✅ NUEVO: Método para cargar configuración de zoom
  Future<void> _loadZoomSettings() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      if (mounted) {
        setState(() {
          _currentZoom = prefs.getDouble('scanner_zoom_level') ?? 0.0;
          _isFixedZoomEnabled = prefs.getBool('scanner_fixed_zoom_enabled') ?? false;
        });
      }
    } catch (e) {
      debugPrint("[ScannerScreen] Error loading zoom settings: $e");
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    final scannerState = ref.read(scannerProvider);
    final scannerNotifier = ref.read(scannerProvider.notifier);

    if (_barcodeFocusNode.hasFocus && scannerState.isCameraActive) {
      scannerNotifier.resetScanner(keepSearchResults: true);
    } else if (!_barcodeFocusNode.hasFocus &&
        !scannerState.isCameraActive &&
        _barcodeController.text.isEmpty &&
        !scannerState.isProcessingBarcode &&
        !_isDialogOpen) {
      debugPrint("[ScannerScreen] Focus lost - restarting scanner");
      scannerNotifier.startScanner();
    }
    setState(() {});
  }

  void _toggleCameraPause() {
    if (!mounted) return;

    final scannerNotifier = ref.read(scannerProvider.notifier);
    final scannerController = scannerNotifier.scannerService.controller;

    if (scannerController == null) return;

    setState(() {
      _isCameraPausedManually = !_isCameraPausedManually;
    });

    try {
      if (_isCameraPausedManually) {
        debugPrint("[ScannerScreen] 🔴 Manual pause");
        scannerController.stop();
        _showSnackBar('Cámara pausada', Colors.orange);
      } else {
        debugPrint("[ScannerScreen] 🟢 Manual resume");
        scannerController.start();
        _showSnackBar('Cámara reanudada', Colors.green);
      }
    } catch (e) {
      debugPrint("[ScannerScreen] ⚠️ Error toggling camera: $e");
    }
  }

  // ✅ NUEVO: Toggle para mostrar/ocultar control de zoom
  void _toggleZoomControl() {
    setState(() {
      _showZoomControl = !_showZoomControl;
    });
  }

  // ✅ NUEVO: Cambiar nivel de zoom
  Future<void> _onZoomChanged(double value) async {
    if (!mounted) return;

    final scannerNotifier = ref.read(scannerProvider.notifier);
    await scannerNotifier.scannerService.setZoomLevel(value);

    setState(() {
      _currentZoom = value;
    });
  }

  // ✅ NUEVO: Toggle zoom fijo
  Future<void> _onFixedZoomToggled(bool enabled) async {
    if (!mounted) return;

    final scannerNotifier = ref.read(scannerProvider.notifier);
    await scannerNotifier.scannerService.setFixedZoomMode(
      enabled: enabled,
      zoomValue: _currentZoom,
    );

    setState(() {
      _isFixedZoomEnabled = enabled;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(enabled
          ? 'Zoom fijo activado (${(_currentZoom * 100).toInt()}%)'
          : 'Zoom automático activado'),
        duration: const Duration(seconds: 2),
        backgroundColor: enabled ? Colors.blue : Colors.grey,
      ),
    );
  }

  // ✅ NUEVO: Zoom in
  Future<void> _zoomIn() async {
    await _onZoomChanged((_currentZoom + 0.1).clamp(0.0, 1.0));
  }

  // ✅ NUEVO: Zoom out
  Future<void> _zoomOut() async {
    await _onZoomChanged((_currentZoom - 0.1).clamp(0.0, 1.0));
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        backgroundColor: color,
      ),
    );
  }

  // ✅ ARREGLO v2.0: Verificar si podemos procesar un escaneo
  bool _canProcessScan() {
    // Si hay un diálogo abierto, no procesar
    if (_isDialogOpen) {
      debugPrint("[ScannerScreen] ⚠️ Diálogo abierto - ignorando escaneo");
      return false;
    }

    // Verificar cooldown
    if (_lastScanTime != null) {
      final elapsed = DateTime.now().difference(_lastScanTime!);
      if (elapsed < _scanCooldown) {
        debugPrint("[ScannerScreen] ⚠️ Cooldown activo (${elapsed.inMilliseconds}ms) - ignorando");
        return false;
      }
    }

    return true;
  }

  // ✅ ARREGLO v2.0: Mostrar diálogo de producto - versión simplificada y robusta
  void _showProductBottomSheet(Product product) {
    if (!mounted) return;

    // Verificar si podemos mostrar el diálogo
    if (!_canProcessScan()) {
      return;
    }

    debugPrint("[ScannerScreen] 📱 Abriendo diálogo para: ${product.name}");

    // Marcar diálogo como abierto y registrar tiempo
    _isDialogOpen = true;
    _lastScanTime = DateTime.now();

    // ✅ FIX: NO pausar cámara - el flag _isDialogOpen previene nuevos escaneos
    // La cámara permanece activa pero _canProcessScan() bloqueará nuevos escaneos
    debugPrint("[ScannerScreen] 📷 Cámara permanece activa (nuevos escaneos bloqueados por flag)");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => AddToCartDialog(productId: product.id),
    ).then((_) {
      debugPrint("[ScannerScreen] ✅ Diálogo cerrado - limpiando estado");
      _onDialogClosed();
    }).catchError((e) {
      debugPrint("[ScannerScreen] ❌ Error en diálogo: $e");
      _onDialogClosed();
    });
  }

  // ✅ ARREGLO v2.0: Pausar cámara de forma segura
  void _pauseCameraSafely() {
    try {
      final scannerNotifier = ref.read(scannerProvider.notifier);
      final controller = scannerNotifier.scannerService.controller;
      if (controller != null) {
        controller.stop();
        debugPrint("[ScannerScreen] 📷 Cámara pausada");
      }
    } catch (e) {
      debugPrint("[ScannerScreen] ⚠️ Error pausando cámara: $e");
    }
  }

  // ✅ ARREGLO v2.1: Callback cuando se cierra el diálogo - CRÍTICO
  void _onDialogClosed() {
    debugPrint("[ScannerScreen] 🔄 _onDialogClosed() ejecutado");

    // IMPORTANTE: Resetear flag de diálogo INMEDIATAMENTE
    _isDialogOpen = false;

    // ✅ FIX v2.1: Usar clearProductFoundState() que ahora verifica y reinicia la cámara
    if (mounted && !_isCameraPausedManually) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isDialogOpen && !_isCameraPausedManually) {
          debugPrint("[ScannerScreen] ✅ Limpiando estado y verificando cámara...");
          ref.read(scannerProvider.notifier).clearProductFoundState();
        }
      });
    }
  }

  // ✅ ARREGLO v2.0: Reanudar cámara de forma segura con reinicio completo si falla
  Future<void> _resumeCameraSafely() async {
    if (!mounted || _isCameraPausedManually || _isDialogOpen) {
      debugPrint("[ScannerScreen] ⚠️ No se puede reanudar: mounted=$mounted, paused=$_isCameraPausedManually, dialog=$_isDialogOpen");
      return;
    }

    debugPrint("[ScannerScreen] 📷 Intentando reanudar cámara...");

    try {
      final scannerNotifier = ref.read(scannerProvider.notifier);
      final controller = scannerNotifier.scannerService.controller;

      if (controller != null) {
        await controller.start();
        debugPrint("[ScannerScreen] ✅ Cámara reanudada con controller.start()");
      } else {
        // No hay controlador - reiniciar escáner completo
        debugPrint("[ScannerScreen] ⚠️ No hay controlador - reiniciando escáner completo");
        await scannerNotifier.resetScanner();
        await scannerNotifier.startScanner();
        debugPrint("[ScannerScreen] ✅ Escáner reiniciado completamente");
      }
    } catch (e) {
      debugPrint("[ScannerScreen] ❌ Error reanudando cámara: $e");

      // FALLBACK: Reiniciar el escáner completamente
      try {
        debugPrint("[ScannerScreen] 🔄 Fallback: reiniciando escáner...");
        final scannerNotifier = ref.read(scannerProvider.notifier);
        await scannerNotifier.resetScanner();

        if (mounted && !_isCameraPausedManually && !_isDialogOpen) {
          await scannerNotifier.startScanner();
          debugPrint("[ScannerScreen] ✅ Fallback exitoso");
        }
      } catch (e2) {
        debugPrint("[ScannerScreen] ❌ Fallback también falló: $e2");
      }
    }
  }

  // ✅ FIX v2: Cerrar cámara completamente sin activar búsqueda ni mostrar botón INICIAR
  Future<void> _closeCameraAndReturnToMain() async {
    debugPrint("[ScannerScreen] 🔴 Cerrando cámara - volviendo a pantalla principal");

    final scannerNotifier = ref.read(scannerProvider.notifier);

    // Resetear el scanner
    await scannerNotifier.resetScanner();

    if (mounted) {
      setState(() {
        _isCameraPausedManually = false;
        _isDialogOpen = false;
      });

      // ✅ Solo limpiar el texto, NO remover foco (eso dispara auto-reinicio del scanner)
      _barcodeController.clear();

      debugPrint("[ScannerScreen] ✅ Cámara cerrada - pantalla principal limpia");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    super.didChangeAppLifecycleState(lifecycleState);
    if (!mounted) return;

    try {
      final scannerState = ref.read(scannerProvider);
      final appStateValue = ref.read(appStateNotifierProvider);

      switch (lifecycleState) {
        case AppLifecycleState.resumed:
          if (mounted &&
              _barcodeController.text.trim().isEmpty &&
              !_barcodeFocusNode.hasFocus &&
              appStateValue.isAppConfigured &&
              !scannerState.isCameraActive &&
              !scannerState.isProcessingBarcode &&
              !_isDialogOpen) {
            debugPrint("[ScannerScreen] App resumed - restarting scanner");
            ref.read(scannerProvider.notifier).startScanner();
          }
          break;
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.hidden:
          if (scannerState.isCameraActive) {
            ref.read(scannerProvider.notifier).resetScanner();
          }
          break;
        case AppLifecycleState.detached:
          break;
      }
    } catch (e) {
      debugPrint("[ScannerScreen] Error in didChangeAppLifecycleState: $e");
    }
  }

  @override
  void dispose() {
    _rapidScanSubscription?.cancel();
    _notificationSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _barcodeController.removeListener(_onSearchTextChanged);
    _barcodeController.dispose();
    _barcodeFocusNode.removeListener(_onFocusChange);
    _barcodeFocusNode.dispose();
    _searchDebounce?.cancel();
    _searchResultsScrollController.removeListener(_onSearchResultsScroll);
    _searchResultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchSettings() async {
    try {
      if (mounted) {
        final prefs = ref.read(sharedPreferencesProvider);
        if (mounted) setState(() => _hideImagesInSearch = prefs.getBool(hideSearchImagePrefKey) ?? false);
      }
    } catch (e) {
      if (mounted) setState(() => _hideImagesInSearch = false);
    }
  }

  void _onSearchTextChanged() {
    final searchText = _barcodeController.text.trim();
    if (_currentSearchQueryForDebounce == searchText) return;
    _currentSearchQueryForDebounce = searchText;
    _searchDebounce?.cancel();
    if (searchText.isNotEmpty) {
      _searchDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted && _barcodeController.text.trim() == searchText) {
          final appStateValue = ref.read(appStateNotifierProvider);
          final scannerNotifier = ref.read(scannerProvider.notifier);
          if (appStateValue.isAppConfigured && appStateValue.isOnline) {
            scannerNotifier.performSearch(searchText);
          } else {
            _showSnackBar(
              appStateValue.isAppConfigured ? "Necesitas conexión para buscar." : "Configura la API para buscar.",
              Colors.orange,
            );
            scannerNotifier.clearSearch();
          }
        }
      });
    } else {
      if (mounted) ref.read(scannerProvider.notifier).clearSearch();
    }
  }

  void _onSearchResultsScroll() {
    final scannerState = ref.read(scannerProvider);
    if (_searchResultsScrollController.position.pixels >= _searchResultsScrollController.position.maxScrollExtent - 200 &&
        scannerState.canLoadMore && !scannerState.isLoadingMore) {
      ref.read(scannerProvider.notifier).loadMoreSearchResults();
    }
  }

  Future<void> _clearSearchAndResetScanner() async {
    _barcodeFocusNode.unfocus();
    _barcodeController.clear();
    if (mounted) await ref.read(scannerProvider.notifier).resetScanner();
  }

  void _setupRapidScanListeners(Scanner scannerNotifier) {
    _rapidScanSubscription?.cancel();
    _notificationSubscription?.cancel();
    if (!mounted) return;

    _rapidScanSubscription = scannerNotifier.onRapidScanSuccess.listen((product) {
      if (mounted) {
        ref.read(currentOrderProvider.notifier).addProduct(product, 1);
        _showSnackBar("'${product.name}' x1 agregado.", Colors.green.shade700);
      }
    });

    _notificationSubscription = scannerNotifier.onScannerNotification.listen((notification) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(notification.message),
            backgroundColor: notification.type == ScannerNotificationType.error
                ? Colors.red.shade700
                : (notification.type == ScannerNotificationType.info ? Colors.blue.shade700 : Colors.grey.shade800),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _showManualBarcodeDialog(BuildContext buildContext) {
    final TextEditingController manualController = TextEditingController();
    final scaffoldMessenger = ScaffoldMessenger.of(buildContext);

    showDialog(
      context: buildContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ingresar Código Manualmente'),
        content: TextField(
          controller: manualController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Escriba el código SKU o de barras'),
          onSubmitted: (value) => _submitManualCode(value, dialogContext, scaffoldMessenger),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => _submitManualCode(manualController.text, dialogContext, scaffoldMessenger),
            child: const Text('BUSCAR'),
          ),
        ],
      ),
    );
  }

  void _submitManualCode(String value, BuildContext dialogContext, ScaffoldMessengerState scaffoldMessenger) {
    final code = value.trim();
    if (mounted && dialogContext.mounted) {
      if (code.isNotEmpty) {
        Navigator.pop(dialogContext);
        final appStateValue = ref.read(appStateNotifierProvider);
        final scannerNotifier = ref.read(scannerProvider.notifier);
        if (appStateValue.isAppConfigured && appStateValue.isOnline) {
          scannerNotifier.scanBarcode(code);
        } else {
          scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(appStateValue.isAppConfigured ? "Necesitas conexión para buscar." : "Configura la API."),
            backgroundColor: Colors.orange,
          ));
        }
      } else {
        scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Ingrese un código'), backgroundColor: Colors.orange));
      }
    }
  }

  void _onBottomNavTap(int index) {
    if (!mounted) return;
    if (index == _currentBottomNavIndex) return;
    setState(() => _currentBottomNavIndex = index);
    if (index == 1) {
      Routes.navigateTo(context, Routes.order).then((_) {
        if (mounted) setState(() => _currentBottomNavIndex = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scannerState = ref.watch(scannerProvider);
    final appStateValue = ref.watch(appStateNotifierProvider);
    final hasSearchQuery = _barcodeController.text.trim().isNotEmpty;
    final shouldShowSearchResultsView = _barcodeFocusNode.hasFocus && hasSearchQuery;
    final showBackButtonInAppBar = shouldShowSearchResultsView;

    // ✅ ARREGLO v2.0: Listener simplificado para productos escaneados
    ref.listen<ScannerState>(
      scannerProvider,
          (previous, next) {
        // Solo procesar cuando cambia a productFound
        if (next.viewState == ScannerViewState.productFound &&
            next.scannedProduct != null &&
            previous?.viewState != ScannerViewState.productFound) {

          debugPrint("[ScannerScreen] 🎯 Producto encontrado: ${next.scannedProduct!.name}");

          // Verificar si podemos procesar
          if (mounted && _canProcessScan()) {
            _showProductBottomSheet(next.scannedProduct!);
          }
        }

        // Auto-reset en error después de 3 segundos
        if (next.viewState == ScannerViewState.error &&
            previous?.viewState != ScannerViewState.error) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_isDialogOpen) {
              ref.read(scannerProvider.notifier).resetScanner();
              ref.read(scannerProvider.notifier).startScanner();
            }
          });
        }

        // Auto-reset cuando no se encuentra producto después de 2 segundos
        if (next.viewState == ScannerViewState.noProduct &&
            previous?.viewState != ScannerViewState.noProduct) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && !_isDialogOpen) {
              ref.read(scannerProvider.notifier).resetScanner();
              ref.read(scannerProvider.notifier).startScanner();
            }
          });
        }
      },
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppHeader(
        title: 'Escáner / Búsqueda',
        showCartButton: true,
        showSettingsButton: false,
        showBackButton: showBackButtonInAppBar,
        onBackPressed: showBackButtonInAppBar ? () => _clearSearchAndResetScanner() : null,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final currentOrderState = ref.watch(currentOrderProvider);
                  return currentOrderState.when(
                    data: (state) {
                      final itemCount = state.order?.items.length ?? 0;
                      final total = state.order?.total ?? 0.0;
                      return itemCount > 0 ? _buildOrderBar(context, itemCount, total) : const SizedBox.shrink();
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
              _buildOfflineIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: TextField(
                  controller: _barcodeController,
                  focusNode: _barcodeFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Buscar producto o escanear código',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: _barcodeController.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _clearSearchAndResetScanner())
                        : null,
                  ),
                ),
              ),
              if (scannerState.rapidScanModeEnabled && !_barcodeFocusNode.hasFocus)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt, color: Colors.blue.shade700, size: 18),
                        const SizedBox(width: 8),
                        Text("Modo de Escaneo Rápido Activado", style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    _buildScannerViewContent(scannerState, appStateValue),
                    if (shouldShowSearchResultsView)
                      _buildSearchResultsOverlay(scannerState, appStateValue),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButtonLocation: const LoweredCenterDockedFabLocation(downwardShift: 10.0),
      floatingActionButton: const DialFloatingActionButton(),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: kBottomNavigationBarHeight,
          child: Row(
            children: <Widget>[
              _buildBottomNavItem(context: context, icon: Icons.qr_code_scanner, label: 'CÓDIGO', itemIndex: 0, onTap: _onBottomNavTap),
              const Spacer(),
              _buildBottomNavItem(context: context, icon: Icons.receipt_long_outlined, label: 'PEDIDOS', itemIndex: 1, onTap: _onBottomNavTap),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsOverlay(ScannerState scannerState, AppState appStateValue) {
    return GestureDetector(
      onTap: () => _clearSearchAndResetScanner(),
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: Column(
          children: [
            Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              elevation: 4.0,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                child: _buildSearchResultsListContent(scannerState, appStateValue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsListContent(ScannerState scannerState, AppState appStateValue) {
    final double bottomPadding = kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom + 24.0;
    if (!appStateValue.isAppConfigured) {
      return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Configure la API para buscar.")));
    }
    if (scannerState.isSearching && scannerState.searchResults.isEmpty) {
      return const _LoadingView(message: "Buscando...");
    }
    if (scannerState.searchErrorText != null && scannerState.searchResults.isEmpty) {
      return _SearchErrorView(searchErrorText: scannerState.searchErrorText!, onRetry: () => _clearSearchAndResetScanner());
    }
    if (scannerState.searchResults.isNotEmpty) {
      return _SearchResultsList(
        searchResults: scannerState.searchResults,
        hideImagesInSearch: _hideImagesInSearch,
        currencyFormat: currencyFormat,
        onProductTap: (product) {
          if (mounted && _canProcessScan()) {
            _showProductBottomSheet(product);
            _clearSearchAndResetScanner();
          }
        },
        bottomPadding: bottomPadding,
        scrollController: _searchResultsScrollController,
        isLoadingMore: scannerState.isLoadingMore,
        canLoadMore: scannerState.canLoadMore,
      );
    }
    if (!scannerState.isSearching && scannerState.searchResults.isEmpty && _barcodeController.text.trim().length > 1) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text("No se encontraron productos.", style: TextStyle(color: Colors.grey)),
      ));
    }
    return const SizedBox.shrink();
  }

  Widget _buildOrderBar(BuildContext context, int itemCount, double total) {
    return InkWell(
      onTap: () {
        if (mounted) {
          ref.read(scannerProvider.notifier).resetScanner();
          Routes.navigateTo(context, Routes.order).then((_) {
            if (mounted) setState(() => _currentBottomNavIndex = 0);
          });
        }
      },
      child: Container(
        color: Theme.of(context).primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(children: [
                Text('PEDIDO ACTUAL', style: TextStyle(color: Colors.grey.shade300, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(12)),
                  child: Text('$itemCount', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Text(currencyFormat.format(total), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineIndicator() {
    return Consumer(
      builder: (context, ref, _) {
        final appStateValue = ref.watch(appStateNotifierProvider);
        if (appStateValue.connectionStatus == ConnectionStatus.offline) {
          return Container(
            color: Colors.orange.shade800,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 14),
                SizedBox(width: 8),
                Text('Modo sin conexión', style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildScannerViewContent(ScannerState scannerState, AppState appStateValue) {
    if (!mounted) return const SizedBox.shrink();

    if (_barcodeFocusNode.hasFocus) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 80, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Escriba para buscar productos por nombre o SKU.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    if (!appStateValue.isAppConfigured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.settings_applications_outlined, size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 24),
              const Text('Configuración Requerida', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Usa el botón "+" y luego "Ajustes" para configurar la conexión con tu tienda WooCommerce.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Capa de Cámara
        if (scannerState.viewState == ScannerViewState.scanning ||
            scannerState.viewState == ScannerViewState.processing ||
            scannerState.viewState == ScannerViewState.productFound)
          _ScannerView(
            scannerState: scannerState,
            onDetect: ref.read(scannerProvider.notifier).handleBarcodeDetection,
            onError: ref.read(scannerProvider.notifier).onScannerError,
            onManualCapture: ref.read(scannerProvider.notifier).triggerManualCapture,
            onTogglePause: _toggleCameraPause,
            isPausedManually: _isCameraPausedManually,
            onCloseCamera: _closeCameraAndReturnToMain,
            // ✅ NUEVOS PARÁMETROS DE ZOOM
            currentZoom: _currentZoom,
            isFixedZoomEnabled: _isFixedZoomEnabled,
            showZoomControl: _showZoomControl,
            onZoomChanged: _onZoomChanged,
            onFixedZoomToggled: _onFixedZoomToggled,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onToggleZoomControl: _toggleZoomControl,
          ),

        // Estados de carga
        if (scannerState.viewState == ScannerViewState.initial)
          const _LoadingView(message: "Inicializando escáner..."),

        if (scannerState.viewState == ScannerViewState.processing)
          const _LoadingView(message: "Procesando código..."),

        // Estados de error
        if (scannerState.viewState == ScannerViewState.noProduct || scannerState.viewState == ScannerViewState.error)
          _ScannerErrorView(
            isNoProduct: scannerState.viewState == ScannerViewState.noProduct,
            errorMessage: scannerState.errorMessage ?? "Error del escáner.",
            onRetry: () => _clearSearchAndResetScanner(),
          ),

        // Estado de activación
        if (scannerState.viewState == ScannerViewState.awaitingActivation)
          _ScannerActivationView(
            onActivateScan: ref.read(scannerProvider.notifier).activateManualScan,
            onManualEntry: () => _showManualBarcodeDialog(context),
          ),
      ],
    );
  }

  Widget _buildBottomNavItem({required BuildContext context, required IconData icon, required String label, required int itemIndex, required Function(int) onTap}) {
    final bool isSelected = itemIndex == _currentBottomNavIndex;
    final Color color = isSelected ? Theme.of(context).primaryColor : Colors.grey.shade600;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(itemIndex),
        borderRadius: BorderRadius.circular(4.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================== WIDGETS AUXILIARES =====================

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

class _SearchErrorView extends StatelessWidget {
  final String searchErrorText;
  final VoidCallback onRetry;
  const _SearchErrorView({required this.searchErrorText, required this.onRetry, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 50),
              const SizedBox(height: 16),
              Text(searchErrorText, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, fontSize: 16)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('LIMPIAR Y REINTENTAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerErrorView extends StatelessWidget {
  final bool isNoProduct;
  final String errorMessage;
  final VoidCallback onRetry;
  const _ScannerErrorView({required this.isNoProduct, required this.errorMessage, required this.onRetry, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isNoProduct ? Icons.search_off : Icons.error_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              Text(errorMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('INTENTAR DE NUEVO')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerActivationView extends StatelessWidget {
  final VoidCallback onActivateScan;
  final VoidCallback onManualEntry;
  const _ScannerActivationView({required this.onActivateScan, required this.onManualEntry, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt_outlined, size: 100, color: Colors.grey.shade400),
              const SizedBox(height: 24),
              const Text('El escáner no está activo', style: TextStyle(fontSize: 18, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Presiona el botón para iniciar o ingresa un código manualmente.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('INICIAR CÁMARA'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                onPressed: onActivateScan,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Ingresar Manualmente'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), textStyle: const TextStyle(fontSize: 14)),
                onPressed: onManualEntry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ✅ ARREGLO v2.0: _ScannerView con callback para cerrar cámara + ZOOM CONTROL
class _ScannerView extends ConsumerWidget {
  final ScannerState scannerState;
  final Function(BarcodeCapture) onDetect;
  final Function(MobileScannerException) onError;
  final VoidCallback? onManualCapture;
  final VoidCallback? onTogglePause;
  final bool isPausedManually;
  final VoidCallback? onCloseCamera;
  // ✅ NUEVO: Props para zoom
  final double currentZoom;
  final bool isFixedZoomEnabled;
  final bool showZoomControl;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<bool> onFixedZoomToggled;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onToggleZoomControl;

  const _ScannerView({
    required this.scannerState,
    required this.onDetect,
    required this.onError,
    this.onManualCapture,
    this.onTogglePause,
    this.isPausedManually = false,
    this.onCloseCamera,
    // ✅ NUEVO
    required this.currentZoom,
    required this.isFixedZoomEnabled,
    required this.showZoomControl,
    required this.onZoomChanged,
    required this.onFixedZoomToggled,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onToggleZoomControl,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scannerNotifier = ref.read(scannerProvider.notifier);
    final scannerController = scannerNotifier.scannerService.controller;

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.expand(
            child: MobileScanner(
              key: const ValueKey('mobile-scanner-widget'),
              controller: scannerController,
              onDetect: onDetect,
              errorBuilder: (context, error) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) onError(error);
                });
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Error cámara: ${error.errorDetails?.message ?? error.errorCode.name}',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Marco de escaneo
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.7), width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            width: MediaQuery.of(context).size.width * 0.7,
            height: MediaQuery.of(context).size.width * 0.7,
          ),
        ),
        // Toggle de modo de captura
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: _buildCaptureModeToggle(context, ref),
        ),
        // Botón de captura manual
        if (scannerState.isManualCaptureMode)
          Positioned(
            bottom: 20,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.camera),
              label: const Text('CAPTURAR'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: onManualCapture,
            ),
          ),
        // ✅ NUEVO: Controles de la derecha (flash, cambiar cámara, zoom)
        if (scannerController != null)
          Positioned(
            top: 80,
            right: 16,
            child: Column(
              children: [
                // Flash toggle
                FloatingActionButton.small(
                  heroTag: 'scannerTorchFAB',
                  onPressed: () => scannerNotifier.toggleTorch(),
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  child: Icon(scannerState.isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                ),
                const SizedBox(height: 8),

                // Camera switch
                FloatingActionButton.small(
                  heroTag: 'scannerCameraSwitchFAB',
                  onPressed: () => scannerController.switchCamera(),
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  child: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                ),
                const SizedBox(height: 8),

                // ✅ NUEVO: Botón para mostrar/ocultar control de zoom
                FloatingActionButton.small(
                  heroTag: 'scannerZoomToggleFAB',
                  onPressed: onToggleZoomControl,
                  backgroundColor: showZoomControl
                      ? Colors.blue.withValues(alpha: 0.8)
                      : Colors.black.withValues(alpha: 0.5),
                  child: Icon(
                    showZoomControl ? Icons.zoom_in : Icons.zoom_out_map,
                    color: Colors.white,
                  ),
                ),

                // ✅ NUEVO: Control de zoom compacto (siempre visible)
                const SizedBox(height: 12),
                ScannerZoomControlCompact(
                  currentZoom: currentZoom,
                  onZoomIn: onZoomIn,
                  onZoomOut: onZoomOut,
                ),
              ],
            ),
          ),
        // ✅ ARREGLO v2.0: Controles de la izquierda (pausar y CERRAR)
        Positioned(
          top: 80,
          left: 16,
          child: Column(
            children: [
              // Botón de pausa/reanudar
              ElevatedButton.icon(
                icon: Icon(isPausedManually ? Icons.play_arrow : Icons.pause, size: 20),
                label: Text(isPausedManually ? "Reanudar" : "Pausar"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPausedManually ? Colors.green.shade700 : Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: onTogglePause,
              ),
              const SizedBox(height: 8),
              // ✅ Botón "Cerrar" que vuelve a modo búsqueda
              ElevatedButton.icon(
                icon: const Icon(Icons.close, size: 20),
                label: const Text("Cerrar"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () {
                  if (onCloseCamera != null) {
                    onCloseCamera!();
                  } else {
                    scannerNotifier.resetScanner();
                  }
                },
              ),
            ],
          ),
        ),

        // ✅ NUEVO: Panel de control de zoom expandido (cuando showZoomControl es true)
        if (showZoomControl)
          Positioned(
            bottom: scannerState.isManualCaptureMode ? 100 : 20,
            child: ScannerZoomControl(
              currentZoom: currentZoom,
              isFixedZoomEnabled: isFixedZoomEnabled,
              onZoomChanged: onZoomChanged,
              onFixedZoomToggled: onFixedZoomToggled,
              onZoomIn: onZoomIn,
              onZoomOut: onZoomOut,
            ),
          ),

        // ✅ NUEVO: Indicador de zoom fijo activo
        if (isFixedZoomEnabled)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Zoom ${(currentZoom * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCaptureModeToggle(BuildContext context, WidgetRef ref) {
    final scannerNotifier = ref.read(scannerProvider.notifier);

    return SegmentedButton<bool>(
      style: SegmentedButton.styleFrom(
        foregroundColor: Theme.of(context).primaryColor,
        backgroundColor: Colors.white.withOpacity(0.85),
        selectedForegroundColor: Colors.white,
        selectedBackgroundColor: Theme.of(context).primaryColor,
        side: BorderSide(color: Colors.grey.shade400, width: 1.5),
      ),
      segments: const [
        ButtonSegment<bool>(value: false, label: Text('Automático')),
        ButtonSegment<bool>(value: true, label: Text('Manual')),
      ],
      selected: {scannerState.isManualCaptureMode},
      onSelectionChanged: (Set<bool> newSelection) {
        scannerNotifier.setManualCaptureMode(newSelection.first);
      },
    );
  }
}

// ===================== LISTA DE RESULTADOS DE BÚSQUEDA =====================

class _SearchResultsList extends StatelessWidget {
  final List<Product> searchResults;
  final bool hideImagesInSearch;
  final NumberFormat currencyFormat;
  final Function(Product) onProductTap;
  final double bottomPadding;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final bool canLoadMore;

  const _SearchResultsList({
    required this.searchResults,
    required this.hideImagesInSearch,
    required this.currencyFormat,
    required this.onProductTap,
    required this.bottomPadding,
    required this.scrollController,
    required this.isLoadingMore,
    required this.canLoadMore,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      itemCount: searchResults.length + (canLoadMore || isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == searchResults.length) {
          return isLoadingMore
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: CircularProgressIndicator()))
              : const SizedBox.shrink();
        }

        final product = searchResults[index];
        final bool canAdd = product.isAvailable;
        final imageUrl = product.displayImageUrl;
        final bool hasValidImage = imageUrl != null && imageUrl.isNotEmpty && Uri.tryParse(imageUrl)?.hasAuthority == true;

        return Card(
          key: ValueKey('${product.id}_${product.dateModified?.millisecondsSinceEpoch ?? index}'),
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canAdd ? () { if (context.mounted) onProductTap(product); } : null,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.grey.shade200),
                    child: (hideImagesInSearch || !hasValidImage)
                        ? Center(child: Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400, size: 30))
                        : CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (c, u) => const Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
                      errorWidget: (c, u, e) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('SKU: ${product.sku.isNotEmpty ? product.sku : "-"}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text(
                          'Stock: ${!product.manageStock ? "Disp." : (product.stockQuantity ?? 0)}',
                          style: TextStyle(color: product.isAvailable ? Colors.green.shade700 : Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(currencyFormat.format(product.displayPrice), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: canAdd ? () { if (context.mounted) onProductTap(product); } : null,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), textStyle: const TextStyle(fontSize: 12), minimumSize: const Size(80, 28)),
                        child: const Text('AGREGAR'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}