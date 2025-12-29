// lib/screens/scanner_screen.dart
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
import '../app.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({Key? key}) : super(key: key);
  @override ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> with WidgetsBindingObserver {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final currencyFormat = NumberFormat.currency(locale: 'es_CR', symbol: '₡');
  Timer? _searchDebounce;
  bool _hideImagesInSearch = false;
  String _currentSearchQueryForDebounce = '';
  int _currentBottomNavIndex = 0;
  bool _isCameraPausedManually = false; // ✅ MEJORA: Estado de pausa manual
  bool _isShowingProductDialog = false; // ✅ FIX: Bandera para prevenir múltiples diálogos simultáneos
  String? _lastProcessedProductId; // ✅ FIX: ID del último producto procesado para evitar duplicados

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
    if (mounted) {
      final scannerNotifier = ref.read(scannerProvider.notifier);
      if (isAppConfigured) await scannerNotifier.startScanner(); else await scannerNotifier.resetScanner(keepSearchResults: true);
      if (mounted) setState(() => _currentBottomNavIndex = 0);
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
        !scannerState.isProcessingBarcode) {
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
        debugPrint("[ScannerScreen] 🔴 Manual pause - stopping camera");
        scannerController.stop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cámara pausada'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        debugPrint("[ScannerScreen] 🟢 Manual resume - starting camera");
        scannerController.start();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cámara reanudada'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("[ScannerScreen] ⚠️ Error toggling camera: $e");
    }
  }

  void _showProductBottomSheet(Product product) {
    if (!mounted) return;

    // ✅ MEJORA: Pausar cámara mientras se muestra el diálogo (ahorro de batería)
    final scannerNotifier = ref.read(scannerProvider.notifier);
    final scannerController = scannerNotifier.scannerService.controller;

    debugPrint("[ScannerScreen] 📱 Showing product bottom sheet - PAUSING camera");

    // Pausar la cámara antes de mostrar el diálogo
    if (scannerController != null) {
      try {
        scannerController.stop();
      } catch (e) {
        debugPrint("[ScannerScreen] ⚠️ Error pausing camera: $e");
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddToCartDialog(productId: product.id),
    ).whenComplete(() {
      debugPrint("[ScannerScreen] Bottom sheet closed - RESUMING scanner");

      // ✅ FIX: Resetear banderas cuando el diálogo se cierra
      _isShowingProductDialog = false;
      _lastProcessedProductId = null; // Permitir escanear el mismo producto nuevamente

      // ✅ MEJORA: Reanudar la cámara después de un delay para evitar pantalla en blanco
      if (mounted && !_isCameraPausedManually) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && scannerController != null && !_isCameraPausedManually) {
            try {
              scannerController.start();
              debugPrint("[ScannerScreen] ✅ Camera resumed successfully");
            } catch (e) {
              debugPrint("[ScannerScreen] ⚠️ Error resuming camera: $e");
              // Si falla, hacer reset completo
              scannerNotifier.resetScanner().then((_) {
                if (mounted && !_isCameraPausedManually) {
                  scannerNotifier.startScanner();
                }
              });
            }
          }
        });
      }
    });
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
              !scannerState.isProcessingBarcode) {
            debugPrint("[ScannerScreen] App resumed - restarting scanner");
            ref.read(scannerProvider.notifier).startScanner();
          }
          break;
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.hidden:
          if (scannerState.isCameraActive) ref.read(scannerProvider.notifier).resetScanner();
          break;
        case AppLifecycleState.detached:
          break;
      }
    } catch (e) {
      debugPrint("[ScannerScreen] CRITICAL ERROR in didChangeAppLifecycleState: $e");
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
      if(mounted){
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
          if(appStateValue.isAppConfigured && appStateValue.isOnline){
            scannerNotifier.performSearch(searchText);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(appStateValue.isAppConfigured ? "Necesitas conexión para buscar." : "Configura la API para buscar."),
                backgroundColor: Colors.orange));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("'${product.name}' x1 agregado."),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(milliseconds: 1500),
          ),
        );
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
        )
    );
  }

  void _submitManualCode(String value, BuildContext dialogContext, ScaffoldMessengerState scaffoldMessenger) {
    final code = value.trim();
    if (mounted && dialogContext.mounted) {
      if (code.isNotEmpty) {
        Navigator.pop(dialogContext);
        final appStateValue = ref.read(appStateNotifierProvider);
        final scannerNotifier = ref.read(scannerProvider.notifier);
        if(appStateValue.isAppConfigured && appStateValue.isOnline){
          scannerNotifier.scanBarcode(code);
        } else {
          scaffoldMessenger.showSnackBar(SnackBar(content: Text(appStateValue.isAppConfigured ? "Necesitas conexión para buscar." : "Configura la API."), backgroundColor: Colors.orange));
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
        if(mounted) setState(() => _currentBottomNavIndex = 0);
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

    ref.listen<ScannerState>(
      scannerProvider,
          (previous, next) {
        if (next.viewState == ScannerViewState.productFound &&
            next.scannedProduct != null &&
            previous?.viewState != ScannerViewState.productFound) {

          debugPrint("[ScannerScreen] 🎯 Product found from scan: ${next.scannedProduct!.name}");

          // ✅ FIX: Verificar bandera Y último producto procesado para prevenir duplicados
          if (mounted && !_isShowingProductDialog && next.scannedProduct!.id != _lastProcessedProductId) {
            _isShowingProductDialog = true; // Marcar INMEDIATAMENTE
            _lastProcessedProductId = next.scannedProduct!.id; // Registrar producto procesado
            debugPrint("[ScannerScreen] 🔵 Opening dialog for product ID: ${next.scannedProduct!.id}");
            _showProductBottomSheet(next.scannedProduct!);
          } else if (_isShowingProductDialog) {
            debugPrint("[ScannerScreen] ⚠️ Prevented duplicate dialog - already showing product dialog");
          } else if (next.scannedProduct!.id == _lastProcessedProductId) {
            debugPrint("[ScannerScreen] ⚠️ Prevented duplicate dialog - same product already processed (ID: ${next.scannedProduct!.id})");
          }
        }

        // También manejar el caso de error - resetear automáticamente después de 3 segundos
        if (next.viewState == ScannerViewState.error &&
            previous?.viewState != ScannerViewState.error) {
          debugPrint("[ScannerScreen] ⚠️ Scanner error detected, will auto-reset");
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              ref.read(scannerProvider.notifier).resetScanner();
              ref.read(scannerProvider.notifier).startScanner();
            }
          });
        }

        // Y manejar el caso de "no product" - resetear automáticamente después de 2 segundos
        if (next.viewState == ScannerViewState.noProduct &&
            previous?.viewState != ScannerViewState.noProduct) {
          debugPrint("[ScannerScreen] 📭 No product found, will auto-resume");
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
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
                    suffixIcon: _barcodeController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _clearSearchAndResetScanner()) : null,
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
                        border: Border.all(color: Colors.blue.shade200)
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
    if (!appStateValue.isAppConfigured) return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Configure la API para buscar.")));
    if (scannerState.isSearching && scannerState.searchResults.isEmpty) return const _LoadingView(message: "Buscando...");
    if (scannerState.searchErrorText != null && scannerState.searchResults.isEmpty) return _SearchErrorView(searchErrorText: scannerState.searchErrorText!, onRetry: () => _clearSearchAndResetScanner());
    if (scannerState.searchResults.isNotEmpty) return _SearchResultsList(searchResults: scannerState.searchResults, hideImagesInSearch: _hideImagesInSearch, currencyFormat: currencyFormat, onProductTap: (product) {
      // ✅ FIX: Verificar bandera Y último producto procesado ANTES de mostrar el diálogo
      if (mounted && !_isShowingProductDialog && product.id != _lastProcessedProductId) {
        _isShowingProductDialog = true;
        _lastProcessedProductId = product.id; // Registrar producto procesado
        _showProductBottomSheet(product);
        _clearSearchAndResetScanner();
      }
    }, bottomPadding: bottomPadding, scrollController: _searchResultsScrollController, isLoadingMore: scannerState.isLoadingMore, canLoadMore: scannerState.canLoadMore);
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
            if(mounted) setState(() => _currentBottomNavIndex = 0);
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
                Text('PEDIDO ACTUAL', style: TextStyle(color: Colors.grey.shade300, fontWeight: FontWeight.bold, fontSize: 14,), overflow: TextOverflow.ellipsis),
                const SizedBox(width: 4), const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(12)), child: Text('$itemCount', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
              ]),
            ),
            const SizedBox(width: 12),
            Text(currencyFormat.format(total), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14,)),
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
            return Container( color: Colors.orange.shade800, padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16), child: const Row( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon( Icons.wifi_off, color: Colors.white, size: 14,), SizedBox(width: 8), Text( 'Modo sin conexión', style: TextStyle( color: Colors.white, fontSize: 12,),), ], ), );
          } else {
            return const SizedBox.shrink();
          }
        }
    );
  }

  Widget _buildScannerViewContent(ScannerState scannerState, AppState appStateValue) {
    if (!mounted) return const SizedBox.shrink();
    if (_barcodeFocusNode.hasFocus) { return Center( child: Padding( padding: const EdgeInsets.all(32.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.search, size: 80, color: Colors.grey.shade300), const SizedBox(height: 16), Text( 'Escriba para buscar productos por nombre o SKU.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ), ], ), ), ); }
    if (!appStateValue.isAppConfigured) { return Center( child: Padding( padding: const EdgeInsets.all(32.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.settings_applications_outlined, size: 80, color: Colors.grey.shade400), const SizedBox(height: 24), const Text( 'Configuración Requerida', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500), textAlign: TextAlign.center,), const SizedBox(height: 12), Text( 'Usa el botón "+" y luego "Ajustes" para configurar la conexión con tu tienda WooCommerce.', style: TextStyle(fontSize: 14, color: Colors.grey.shade700), textAlign: TextAlign.center, ), ], ), ), ); }

    // 🔥 FIX: Mantener el widget de la cámara SIEMPRE visible en el stack
    // si el estado es scanning, processing O productFound.
    // Esto evita que se destruya la superficie de la cámara cuando se encuentra un producto.
    return Stack(
      children: [
        // 1. Capa de Cámara (Fondo) - Se mantiene viva durante productFound
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
          ),

        // 2. Capas de Estado (superpuestas)
        if (scannerState.viewState == ScannerViewState.initial)
          const _LoadingView(message: "Inicializando escáner..."),

        if (scannerState.viewState == ScannerViewState.processing)
          const _LoadingView(message: "Procesando código..."),

        // Nota: Ya no mostramos _LoadingView para productFound porque tapa la cámara
        // y el BottomSheet ya indica que se encontró algo.

        if (scannerState.viewState == ScannerViewState.noProduct || scannerState.viewState == ScannerViewState.error)
          _ScannerErrorView(
              isNoProduct: scannerState.viewState == ScannerViewState.noProduct,
              errorMessage: scannerState.errorMessage ?? "Error del escáner.",
              onRetry: () => _clearSearchAndResetScanner()
          ),

        if (scannerState.viewState == ScannerViewState.awaitingActivation)
          _ScannerActivationView(
              onActivateScan: ref.read(scannerProvider.notifier).activateManualScan,
              onManualEntry: () => _showManualBarcodeDialog(context)
          ),
      ],
    );
  }

  Widget _buildBottomNavItem({ required BuildContext context, required IconData icon, required String label, required int itemIndex, required Function(int) onTap}) {
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

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message, Key? key}) : super(key: key);
  @override Widget build(BuildContext context) { return Center( child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ const CircularProgressIndicator(), const SizedBox(height: 16), Text(message), ], ), ); }
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
              Text( searchErrorText, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, fontSize: 16), ),
              const SizedBox(height: 24),
              ElevatedButton.icon( style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)), onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('LIMPIAR Y REINTENTAR'), ),
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
  const _ScannerErrorView({ required this.isNoProduct, required this.errorMessage, required this.onRetry, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon( isNoProduct ? Icons.search_off : Icons.error_outline, size: 80, color: Colors.grey, ),
              const SizedBox(height: 16),
              Text( errorMessage, textAlign: TextAlign.center, style: const TextStyle( fontSize: 16, color: Colors.grey,), ),
              const SizedBox(height: 24),
              ElevatedButton.icon( onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('INTENTAR DE NUEVO'), ),
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
  const _ScannerActivationView({ required this.onActivateScan, required this.onManualEntry, Key? key }) : super(key: key);
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
              const Text( 'El escáner no está activo', style: TextStyle(fontSize: 18, color: Colors.grey), textAlign: TextAlign.center,),
              const SizedBox(height: 8),
              const Text( 'Presiona el botón para iniciar o ingresa un código manualmente.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center,),
              const SizedBox(height: 32),
              ElevatedButton.icon( icon: const Icon(Icons.qr_code_scanner), label: const Text('INICIAR CÁMARA'), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), ), onPressed: onActivateScan, ),
              const SizedBox(height: 24),
              OutlinedButton.icon( icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Ingresar Manualmente'), style: OutlinedButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), textStyle: const TextStyle(fontSize: 14), ), onPressed: onManualEntry, )
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerView extends ConsumerWidget {
  final ScannerState scannerState;
  final Function(BarcodeCapture) onDetect;
  final Function(MobileScannerException) onError;
  final VoidCallback? onManualCapture;
  final VoidCallback? onTogglePause; // ✅ MEJORA: Callback para pausa manual
  final bool isPausedManually; // ✅ MEJORA: Estado de pausa manual

  const _ScannerView({
    required this.scannerState,
    required this.onDetect,
    required this.onError,
    this.onManualCapture,
    this.onTogglePause,
    this.isPausedManually = false,
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
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration( border: Border.all( color: Theme.of(context).primaryColor.withOpacity(0.7), width: 3, ), borderRadius: BorderRadius.circular(12), ),
            width: MediaQuery.of(context).size.width * 0.7,
            height: MediaQuery.of(context).size.width * 0.7,
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: _buildCaptureModeToggle(context, ref),
        ),
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
        Positioned(
          top: 80,
          right: 16,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'scannerTorchFAB_ScannerView',
                onPressed: () { scannerNotifier.toggleTorch(); },
                backgroundColor: Colors.black.withOpacity(0.5),
                child: Icon(scannerState.isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'scannerCameraSwitchFAB_ScannerView',
                onPressed: () { scannerController.switchCamera(); },
                backgroundColor: Colors.black.withOpacity(0.5),
                child: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
              ),
            ],
          ),
        ),
        Positioned(
          top: 80,
          left: 16,
          child: Column(
            children: [
              // ✅ MEJORA: Botón de pausa/reanudar manual
              ElevatedButton.icon(
                icon: Icon(
                  isPausedManually ? Icons.play_arrow : Icons.pause,
                  size: 20,
                ),
                label: Text(isPausedManually ? "Reanudar" : "Pausar"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPausedManually
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: onTogglePause,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.close, size: 20),
                label: const Text("Cerrar"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () async {
                  // ✅ FIX: Solo cerrar la cámara y volver a modo búsqueda manual
                  // NO salir de la pantalla del scanner
                  await scannerNotifier.resetScanner();
                  debugPrint("[ScannerScreen] 🔴 Cámara cerrada - volviendo a modo búsqueda manual");
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureModeToggle(BuildContext context, WidgetRef ref) {
    final scannerState = ref.watch(scannerProvider);
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
              ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Center(child: CircularProgressIndicator()),
          )
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
                    width: 60, height: 60,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration( borderRadius: BorderRadius.circular(4), color: Colors.grey.shade200 ),
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
                        Text( product.name, style: const TextStyle( fontWeight: FontWeight.bold,), maxLines: 2, overflow: TextOverflow.ellipsis, ),
                        const SizedBox(height: 4),
                        Text( 'SKU: ${product.sku.isNotEmpty ? product.sku : "-"}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600) ),
                        Text(
                          'Stock: ${!product.manageStock ? "Disp." : (product.stockQuantity ?? 0)}',
                          style: TextStyle( color: product.isAvailable ? Colors.green.shade700 : Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.w500 ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text( currencyFormat.format(product.displayPrice), style: const TextStyle( fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87), ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: canAdd ? () { if (context.mounted) onProductTap(product); } : null,
                        style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric( horizontal: 10, vertical: 4,), textStyle: const TextStyle(fontSize: 12), minimumSize: const Size(80, 28), ),
                        child: const Text('AGREGAR'),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}