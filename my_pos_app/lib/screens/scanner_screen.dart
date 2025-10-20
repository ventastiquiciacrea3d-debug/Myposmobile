// lib/screens/scanner_screen.dart
import 'dart.async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import '../providers/scanner_provider.dart' show ScannerProvider, ScannerViewState, ScannerNotification, ScannerNotificationType;
import '../providers/order_provider.dart';
import '../providers/app_state_provider.dart';
import '../widgets/app_header.dart';
import '../config/constants.dart';
import '../config/routes.dart';
import '../widgets/dial_floating_action_button.dart';
import '../widgets/custom_fab_location.dart';
import '../widgets/add_to_cart_dialog.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({Key? key}) : super(key: key);
  @override State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final currencyFormat = NumberFormat.currency(locale: 'es_CR', symbol: '₡');
  Timer? _searchDebounce;
  bool _hideImagesInSearch = false;
  String _currentSearchQueryForDebounce = '';
  bool _appStateListenerAdded = false;
  int _currentBottomNavIndex = 0;

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
      final appState = context.read<AppStateProvider>();
      final scannerProvider = context.read<ScannerProvider>();

      scannerProvider.addListener(_onScannerStateChanged);
      _setupRapidScanListeners(scannerProvider);

      if (!appState.isLoading) {
        _loadSettingsAndInitScanner(appState.isAppConfigured);
      } else {
        appState.addListener(_onAppStateChangeForScannerInit);
        _appStateListenerAdded = true;
      }
    });
  }

  void _onAppStateChangeForScannerInit() {
    if (!mounted) return;
    final appState = context.read<AppStateProvider>();
    if (!appState.isLoading) {
      if (_appStateListenerAdded) {
        try { appState.removeListener(_onAppStateChangeForScannerInit); } catch (e) { debugPrint("... Error removing listener _onAppStateChangeForScannerInit: $e"); }
        _appStateListenerAdded = false;
      }
      _loadSettingsAndInitScanner(appState.isAppConfigured);
    }
  }

  Future<void> _loadSettingsAndInitScanner(bool isAppConfigured) async {
    await _loadSearchSettings();
    if (mounted) {
      final scannerProvider = context.read<ScannerProvider>();
      if (isAppConfigured) await scannerProvider.startScanner(); else await scannerProvider.resetScanner(keepSearchResults: true);
      if (mounted) setState(() => _currentBottomNavIndex = 0);
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    final scannerProvider = context.read<ScannerProvider>();
    if (_barcodeFocusNode.hasFocus && scannerProvider.isCameraActive) {
      scannerProvider.resetScanner(keepSearchResults: true);
    } else if (!_barcodeFocusNode.hasFocus && !scannerProvider.isCameraActive && _barcodeController.text.isEmpty) {
      scannerProvider.startScanner();
    }
    setState(() {});
  }

  void _onScannerStateChanged() {
    if (!mounted) return;
    final scannerProvider = context.read<ScannerProvider>();
    if (scannerProvider.state == ScannerViewState.productFound && scannerProvider.scannedProduct != null) {
      if (mounted) _showProductBottomSheet(scannerProvider.scannedProduct!);
    }
  }

  void _showProductBottomSheet(Product product) {
    if (!mounted) return;
    context.read<ScannerProvider>().resetScanner();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => AddToCartDialog(productId: product.id),
    ).whenComplete(() {
      if (mounted) context.read<ScannerProvider>().resumeScanning();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    try {
      final scannerProvider = context.read<ScannerProvider>();
      final appStateProvider = context.read<AppStateProvider>();
      if (scannerProvider.isDisposed || appStateProvider.isDisposed) return;

      switch (state) {
        case AppLifecycleState.resumed:
          if (mounted && _barcodeController.text.trim().isEmpty && !_barcodeFocusNode.hasFocus && appStateProvider.isAppConfigured) {
            scannerProvider.startScanner();
          }
          break;
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.hidden:
          if (scannerProvider.isCameraActive) scannerProvider.resetScanner();
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
    try {
      context.read<ScannerProvider>().removeListener(_onScannerStateChanged);
    } catch (e) { debugPrint("[ScannerScreen] Error removing listener in dispose: ${e.toString()}"); }
    if (_appStateListenerAdded) {
      try {
        Provider.of<AppStateProvider>(context, listen: false).removeListener(_onAppStateChangeForScannerInit);
      } catch (e) { debugPrint("... Error removing listener in dispose: ${e.toString()}"); }
    }
    super.dispose();
  }

  Future<void> _loadSearchSettings() async {
    try {
      if(mounted){
        final prefs = context.read<SharedPreferences>();
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
          final appState = context.read<AppStateProvider>();
          final scannerProvider = context.read<ScannerProvider>();
          if (scannerProvider.isDisposed) return;
          if(appState.isAppConfigured && appState.connectionStatus == ConnectionStatus.online){
            scannerProvider.performSearch(searchText);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(appState.isAppConfigured ? "Necesitas conexión para buscar." : "Configura la API para buscar."),
                backgroundColor: Colors.orange));
            scannerProvider.clearSearch();
          }
        }
      });
    } else {
      if (mounted) context.read<ScannerProvider>().clearSearch();
    }
  }

  void _onSearchResultsScroll() {
    final scannerProvider = context.read<ScannerProvider>();
    if (scannerProvider.isDisposed) return;
    if (_searchResultsScrollController.position.pixels >= _searchResultsScrollController.position.maxScrollExtent - 200 &&
        scannerProvider.canLoadMore && !scannerProvider.isLoadingMore) {
      scannerProvider.loadMoreSearchResults();
    }
  }

  Future<void> _clearSearchAndResetScanner() async {
    _barcodeFocusNode.unfocus();
    _barcodeController.clear();
    if (mounted) await context.read<ScannerProvider>().resetScanner();
  }

  void _setupRapidScanListeners(ScannerProvider provider) {
    _rapidScanSubscription?.cancel();
    _notificationSubscription?.cancel();
    if (!mounted) return;

    _rapidScanSubscription = provider.onRapidScanSuccess.listen((product) {
      if (mounted) {
        context.read<OrderProvider>().addProduct(product, 1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("'${product.name}' x1 agregado."),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    });

    _notificationSubscription = provider.onScannerNotification.listen((notification) {
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
    final scannerProvider = Provider.of<ScannerProvider>(buildContext, listen: false);
    final appState = Provider.of<AppStateProvider>(buildContext, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(buildContext);

    showDialog(
        context: buildContext,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ingresar Código Manualmente'),
          content: TextField(
            controller: manualController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Escriba el código SKU o de barras'),
            onSubmitted: (value) => _submitManualCode(value, dialogContext, appState, scannerProvider, scaffoldMessenger),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
            TextButton(
              onPressed: () => _submitManualCode(manualController.text, dialogContext, appState, scannerProvider, scaffoldMessenger),
              child: const Text('BUSCAR'),
            ),
          ],
        )
    );
  }

  void _submitManualCode(String value, BuildContext dialogContext, AppStateProvider appState, ScannerProvider scannerProvider, ScaffoldMessengerState scaffoldMessenger) {
    final code = value.trim();
    if (mounted && dialogContext.mounted) {
      if (code.isNotEmpty) {
        Navigator.pop(dialogContext);
        if(appState.isAppConfigured && appState.connectionStatus == ConnectionStatus.online){
          scannerProvider.scanBarcode(code);
        } else {
          scaffoldMessenger.showSnackBar(SnackBar(content: Text(appState.isAppConfigured ? "Necesitas conexión para buscar." : "Configura la API."), backgroundColor: Colors.orange));
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
    final scannerProvider = context.watch<ScannerProvider>();
    final appState = context.watch<AppStateProvider>();
    final hasSearchQuery = _barcodeController.text.trim().isNotEmpty;
    final shouldShowSearchResultsView = _barcodeFocusNode.hasFocus && hasSearchQuery;
    final showBackButtonInAppBar = shouldShowSearchResultsView;

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
              Selector<OrderProvider, ({int count, double total})>(
                  selector: (_, provider) => (count: provider.currentOrder?.items.length ?? 0, total: provider.currentOrder?.total ?? 0.0),
                  builder: (context, orderData, _) => orderData.count > 0 ? _buildOrderBar(context, orderData.count, orderData.total) : const SizedBox.shrink()
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
              if (scannerProvider.rapidScanModeEnabled && !_barcodeFocusNode.hasFocus)
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
                    _buildScannerViewContent(scannerProvider, appState),
                    if (shouldShowSearchResultsView)
                      _buildSearchResultsOverlay(scannerProvider, appState),
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

  Widget _buildSearchResultsOverlay(ScannerProvider scannerProvider, AppStateProvider appState) {
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
                child: _buildSearchResultsListContent(scannerProvider, appState),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsListContent(ScannerProvider scannerProvider, AppStateProvider appState) {
    final double bottomPadding = kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom + 24.0;
    if (!appState.isAppConfigured) return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Configure la API para buscar.")));
    if (scannerProvider.isSearching && scannerProvider.searchResults.isEmpty) return _LoadingView(message: "Buscando...");
    if (scannerProvider.searchErrorText != null && scannerProvider.searchResults.isEmpty) return _SearchErrorView(searchErrorText: scannerProvider.searchErrorText!, onRetry: () => _clearSearchAndResetScanner());
    if (scannerProvider.searchResults.isNotEmpty) return _SearchResultsList(searchResults: scannerProvider.searchResults, hideImagesInSearch: _hideImagesInSearch, currencyFormat: currencyFormat, onProductTap: (product) {
      if (mounted) {
        _showProductBottomSheet(product);
        _clearSearchAndResetScanner();
      }
    }, bottomPadding: bottomPadding, scrollController: _searchResultsScrollController, isLoadingMore: scannerProvider.isLoadingMore, canLoadMore: scannerProvider.canLoadMore);
    if (!scannerProvider.isSearching && scannerProvider.searchResults.isEmpty && _barcodeController.text.trim().length > 1) {
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
          context.read<ScannerProvider>().resetScanner();
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
    return Selector<AppStateProvider, ConnectionStatus>(
        selector: (_, provider) => provider.connectionStatus,
        builder: (context, status, _) {
          if (status == ConnectionStatus.offline) {
            return Container( color: Colors.orange.shade800, padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16), child: const Row( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon( Icons.wifi_off, color: Colors.white, size: 14,), SizedBox(width: 8), Text( 'Modo sin conexión', style: TextStyle( color: Colors.white, fontSize: 12,),), ], ), );
          } else {
            return const SizedBox.shrink();
          }
        }
    );
  }

  Widget _buildScannerViewContent(ScannerProvider scannerProvider, AppStateProvider appState) {
    if (!mounted || scannerProvider.isDisposed) return const SizedBox.shrink();
    if (_barcodeFocusNode.hasFocus) { return Center( child: Padding( padding: const EdgeInsets.all(32.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.search, size: 80, color: Colors.grey.shade300), const SizedBox(height: 16), Text( 'Escriba para buscar productos por nombre o SKU.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ), ], ), ), ); }
    if (!appState.isAppConfigured) { return Center( child: Padding( padding: const EdgeInsets.all(32.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.settings_applications_outlined, size: 80, color: Colors.grey.shade400), const SizedBox(height: 24), const Text( 'Configuración Requerida', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500), textAlign: TextAlign.center,), const SizedBox(height: 12), Text( 'Usa el botón "+" y luego "Ajustes" para configurar la conexión con tu tienda WooCommerce.', style: TextStyle(fontSize: 14, color: Colors.grey.shade700), textAlign: TextAlign.center, ), ], ), ), ); }
    switch (scannerProvider.state) {
      case ScannerViewState.initial: return const _LoadingView(message: "Inicializando escáner...");
      case ScannerViewState.scanning: return _ScannerView( scannerProvider: scannerProvider, onDetect: scannerProvider.handleBarcodeDetection, onError: scannerProvider.onScannerError, onManualCapture: scannerProvider.triggerManualCapture, );
      case ScannerViewState.processing: return const _LoadingView(message: "Procesando código...");
      case ScannerViewState.productFound: return const _LoadingView(message: "Producto encontrado...");
      case ScannerViewState.noProduct: case ScannerViewState.error: return _ScannerErrorView( isNoProduct: scannerProvider.state == ScannerViewState.noProduct, errorMessage: scannerProvider.errorMessage ?? "Error del escáner.", onRetry: () => _clearSearchAndResetScanner() );
      case ScannerViewState.awaitingActivation: default: return _ScannerActivationView(onActivateScan: scannerProvider.activateManualScan, onManualEntry: () => _showManualBarcodeDialog(context));
    }
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

class _ScannerView extends StatelessWidget {
  final ScannerProvider scannerProvider;
  final Function(BarcodeCapture) onDetect;
  final Function(MobileScannerException) onError;
  final VoidCallback? onManualCapture;

  const _ScannerView({
    required this.scannerProvider,
    required this.onDetect,
    required this.onError,
    this.onManualCapture,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (scannerProvider.isDisposed) {
      return const Center(child: Text("Scanner no disponible."));
    }
    final scannerController = scannerProvider.scannerService.controller;

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
              errorBuilder: (context, error, child) {
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
          child: _buildCaptureModeToggle(context, scannerProvider),
        ),
        if (scannerProvider.isManualCaptureMode)
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
                onPressed: () { if (!scannerProvider.isDisposed) scannerProvider.toggleTorch(); },
                backgroundColor: Colors.black.withOpacity(0.5),
                child: Icon(scannerProvider.isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'scannerCameraSwitchFAB_ScannerView',
                onPressed: () { if (!scannerProvider.isDisposed) scannerController.switchCamera(); },
                backgroundColor: Colors.black.withOpacity(0.5),
                child: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
              ),
            ],
          ),
        ),
        Positioned(
          top: 80,
          left: 16,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: const Text("Detener"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: () {
              if (!scannerProvider.isDisposed) {
                scannerProvider.resetScanner();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureModeToggle(BuildContext context, ScannerProvider scannerProvider) {
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
      selected: {scannerProvider.isManualCaptureMode},
      onSelectionChanged: (Set<bool> newSelection) {
        scannerProvider.setManualCaptureMode(newSelection.first);
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