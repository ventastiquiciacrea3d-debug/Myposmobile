// lib/providers/scanner_notifier.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../models/product.dart';
import '../services/scanner_service.dart';
import '../repositories/product_repository.dart';
import '../config/constants.dart';
import 'scanner_state.dart';
import 'shared_providers.dart';

part 'scanner_notifier.g.dart';

/// ✓ FASE 2 RIVERPOD: Scanner Notifier
@riverpod
class Scanner extends _$Scanner {
  late ScannerService _scannerService;
  late ProductRepository _productRepository;
  late SharedPreferences _prefs;

  // Stream controllers
  final StreamController<Product> _rapidScanProductController = StreamController.broadcast();
  final StreamController<ScannerNotification> _scannerNotificationController = StreamController.broadcast();

  StreamSubscription? _productUpdateSubscription;
  bool _isStartingCamera = false;
  bool _isStoppingCamera = false;

  static const int _productsPerPage = 20;

  Stream<Product> get onRapidScanSuccess => _rapidScanProductController.stream;
  Stream<ScannerNotification> get onScannerNotification => _scannerNotificationController.stream;
  ScannerService get scannerService => _scannerService;

  @override
  ScannerState build() {
    debugPrint("[Scanner] build() called - Initializing");

    _scannerService = ref.read(scannerServiceProvider);
    _productRepository = ref.read(productRepositoryProvider);
    _prefs = ref.read(sharedPreferencesProvider);

    ref.onDispose(() {
      debugPrint("[Scanner] Disposing");
      _productUpdateSubscription?.cancel();
      _rapidScanProductController.close();
      _scannerNotificationController.close();
      _scannerService.dispose();
    });

    // ✓ CORRECCIÓN RACE CONDITION: Diferir la carga de settings después de build()
    // para prevenir el error "Tried to read the state of an uninitialized provider"
    Future.microtask(() {
      _loadSettings();
      _listenToProductUpdatesFromRepository();
    });

    return ScannerState.initial();
  }

  void _loadSettings() {
    try {
      final manualScanMode = _prefs.getBool(manualScanModePrefKey) ?? false;
      final rapidScanMode = _prefs.getBool(rapidScanModePrefKey) ?? false;

      state = state.copyWith(
        manualScanModeEnabled: manualScanMode,
        rapidScanModeEnabled: rapidScanMode,
      );

      debugPrint("[Scanner] Settings loaded - Manual: $manualScanMode, Rapid: $rapidScanMode");
    } catch (e) {
      debugPrint("[Scanner] Error loading settings: $e");
    }
  }

  void _listenToProductUpdatesFromRepository() {
    _productUpdateSubscription?.cancel();
    _productUpdateSubscription = _productRepository.onProductUpdatedFromApi.listen(
      (updatedProductFull) {
        // Update scanned product if it matches
        if (state.scannedProduct?.id == updatedProductFull.id) {
          state = state.copyWith(scannedProduct: updatedProductFull);
        }

        // Update search results if product is in list
        final index = state.searchResults.indexWhere((p) => p.id == updatedProductFull.id);
        if (index != -1) {
          final updatedResults = List<Product>.from(state.searchResults);
          updatedResults[index] = updatedProductFull;
          state = state.copyWith(searchResults: updatedResults);
        }
      },
    );
  }

  // ========== SEARCH METHODS ==========

  Future<void> performSearch(String query) async {
    final trimmedQuery = query.trim();

    if (state.currentSearchQuery == trimmedQuery && state.isSearching) {
      return;
    }

    state = state.copyWith(currentSearchQuery: trimmedQuery);

    if (trimmedQuery.length < 2) {
      clearSearch();
      return;
    }

    state = state.copyWith(
      currentPage: 1,
      searchResults: [],
      isSearching: true,
      searchErrorText: null,
    );

    try {
      // ✅ FIX: Usar búsqueda local primero (más rápida)
      final apiResponse = await _productRepository.searchProductsByTerm(
        trimmedQuery,
        page: 1,
        limit: _productsPerPage,
        localOnly: true, // ✅ Solo buscar en BD local para velocidad instantánea
        onCachedResults: (cachedResults) {
          if (state.currentSearchQuery != trimmedQuery) return;

          state = state.copyWith(
            searchResults: cachedResults,
            isSearching: true,
            canLoadMore: false,
          );
        },
      );

      if (state.currentSearchQuery != trimmedQuery) return;

      final products = (apiResponse['products'] as List?)?.cast<Product>() ?? [];
      final totalProducts = apiResponse['total_products'] as int? ?? 0;
      final totalPages = apiResponse['total_pages'] as int? ?? 1;

      state = state.copyWith(
        searchResults: products,
        totalProducts: totalProducts,
        totalPages: totalPages,
        canLoadMore: 1 < totalPages,
        searchErrorText: products.isEmpty
            ? "No se encontraron productos para: '$trimmedQuery'"
            : null,
      );
    } catch (e) {
      if (state.currentSearchQuery != trimmedQuery) return;

      state = state.copyWith(
        searchErrorText: 'Error: ${e.toString()}.',
      );
    } finally {
      if (state.currentSearchQuery == trimmedQuery) {
        state = state.copyWith(isSearching: false);
      }
    }
  }

  Future<void> loadMoreSearchResults() async {
    if (state.isLoadingMore ||
        !state.canLoadMore ||
        state.currentSearchQuery.isEmpty) {
      return;
    }

    final nextPage = state.currentPage + 1;
    final currentQuery = state.currentSearchQuery;

    state = state.copyWith(
      isLoadingMore: true,
      currentPage: nextPage,
    );

    try {
      // ✅ FIX: Paginación también usa búsqueda local
      final apiResponse = await _productRepository.searchProductsByTerm(
        currentQuery,
        page: nextPage,
        limit: _productsPerPage,
        localOnly: true, // ✅ Solo buscar en BD local
      );

      if (state.currentSearchQuery != (apiResponse['query'] ?? '')) return;

      final newProducts = (apiResponse['products'] as List?)?.cast<Product>() ?? [];

      if (newProducts.isNotEmpty) {
        final updatedResults = [...state.searchResults, ...newProducts];
        final totalProducts = apiResponse['total_products'] as int? ?? updatedResults.length;
        final totalPages = apiResponse['total_pages'] as int? ?? 1;

        state = state.copyWith(
          searchResults: updatedResults,
          totalProducts: totalProducts,
          totalPages: totalPages,
          canLoadMore: nextPage < totalPages,
        );
      }
    } catch (e) {
      state = state.copyWith(
        searchErrorText: "Error al cargar más: ${e.toString()}.",
        canLoadMore: false,
      );
    } finally {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void clearSearch() {
    if (state.currentSearchQuery.isNotEmpty ||
        state.searchResults.isNotEmpty ||
        state.isSearching ||
        state.searchErrorText != null ||
        state.totalProducts > 0) {

      state = state.copyWith(
        currentSearchQuery: '',
        searchResults: [],
        isSearching: false,
        searchErrorText: null,
        currentPage: 1,
        totalProducts: 0,
        totalPages: 1,
        canLoadMore: false,
        isLoadingMore: false,
      );
    }
  }

  // ========== CAMERA CONTROL METHODS ==========

  Future<void> _startCamera() async {
    if (state.isCameraActive) {
      debugPrint("[Scanner] _startCamera() skipped - camera already active");
      return;
    }

    if (_isStartingCamera) {
      debugPrint("[Scanner] _startCamera() skipped - start in progress");
      return;
    }

    _isStartingCamera = true;
    debugPrint("[Scanner] _startCamera() - Starting camera");
    state = state.copyWith(viewState: ScannerViewState.scanning);

    try {
      await _scannerService.startScanner();
      state = state.copyWith(isCameraActive: true);
      debugPrint("[Scanner] Camera started successfully");
    } catch (e) {
      state = state.copyWith(
        viewState: ScannerViewState.error,
        errorMessage: "Error al iniciar la cámara: ${e.toString()}",
        isCameraActive: false,
      );
      debugPrint("[Scanner] Error starting camera: $e");
    } finally {
      _isStartingCamera = false;
    }
  }

  Future<void> _stopCamera() async {
    if (!state.isCameraActive) {
      debugPrint("[Scanner] _stopCamera() skipped - camera already inactive");
      return;
    }

    if (_isStoppingCamera) {
      debugPrint("[Scanner] _stopCamera() skipped - stop in progress");
      return;
    }

    _isStoppingCamera = true;
    debugPrint("[Scanner] _stopCamera() - Stopping camera");

    try {
      await _scannerService.stopScanner();
      debugPrint("[Scanner] Camera stopped successfully");
    } catch (e) {
      debugPrint("[Scanner] Error stopping camera: $e");
    } finally {
      _isStoppingCamera = false;

      final newViewState = state.manualScanModeEnabled
          ? ScannerViewState.awaitingActivation
          : ScannerViewState.initial;

      state = state.copyWith(
        isCameraActive: false,
        isTorchOn: false,
        viewState: newViewState,
      );
    }
  }

  Future<void> startScanner() async {
    debugPrint("[Scanner] startScanner() called");
    _loadSettings();

    if (state.manualScanModeEnabled) {
      if (state.viewState != ScannerViewState.awaitingActivation) {
        state = state.copyWith(viewState: ScannerViewState.awaitingActivation);
      }
    } else {
      await _startCamera();
    }
  }

  Future<void> activateManualScan() async {
    if (state.manualScanModeEnabled && !state.isCameraActive) {
      await _startCamera();
    }
  }

  Future<void> toggleTorch() async {
    try {
      await _scannerService.toggleTorch();
      state = state.copyWith(isTorchOn: !state.isTorchOn);
      debugPrint("[Scanner] Torch toggled: ${state.isTorchOn}");
    } catch (e) {
      debugPrint("[Scanner] Error toggling torch: $e");
    }
  }

  void setManualCaptureMode(bool enabled) {
    if (state.isManualCaptureMode == enabled) return;

    state = state.copyWith(
      isManualCaptureMode: enabled,
      latestBarcodeCapture: null,
    );

    debugPrint("[Scanner] Manual capture mode: $enabled");
  }

  // ========== BARCODE SCANNING METHODS ==========

  Future<void> scanBarcode(String barcode) async {
    state = state.copyWith(
      viewState: ScannerViewState.processing,
      errorMessage: null,
      scannedProduct: null,
    );

    try {
      final product = await _productRepository.searchProductByBarcodeOrSku(barcode);

      if (product == null) {
        state = state.copyWith(
          viewState: ScannerViewState.noProduct,
          errorMessage: "Producto no encontrado para el código '$barcode'.",
        );
      } else {
        state = state.copyWith(
          scannedProduct: product,
          viewState: ScannerViewState.productFound,
          errorMessage: null,
        );
      }

      debugPrint("[Scanner] Barcode scan result for '$barcode': ${product?.name ?? 'Not found'}");
    } catch (e) {
      state = state.copyWith(
        viewState: ScannerViewState.error,
        errorMessage: "Ocurrió un error: ${e.toString()}",
      );
      debugPrint("[Scanner] Error scanning barcode: $e");
    }
  }

  void handleBarcodeDetection(BarcodeCapture capture) {
    if (state.viewState != ScannerViewState.scanning) return;

    if (state.isManualCaptureMode) {
      state = state.copyWith(latestBarcodeCapture: capture);
    } else {
      _processBarcodeCapture(capture);
    }
  }

  Future<void> triggerManualCapture() async {
    if (state.latestBarcodeCapture != null) {
      await _processBarcodeCapture(state.latestBarcodeCapture!);
      state = state.copyWith(latestBarcodeCapture: null);
    }
  }

  Future<void> _processBarcodeCapture(BarcodeCapture capture) async {
    if (state.isProcessingBarcode) {
      debugPrint("[Scanner] _processBarcodeCapture() skipped - already processing");
      return;
    }

    if (state.viewState != ScannerViewState.scanning) {
      debugPrint("[Scanner] _processBarcodeCapture() skipped - not in scanning state");
      return;
    }

    final String? foundCode = capture.barcodes
        .firstWhereOrNull((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
        ?.rawValue;

    if (foundCode == null) return;

    state = state.copyWith(isProcessingBarcode: true);
    debugPrint("[Scanner] Processing barcode: $foundCode");

    // Stop camera if not in rapid scan mode
    if (!state.rapidScanModeEnabled) {
      await _scannerService.stopScanner();
      state = state.copyWith(isCameraActive: false);
    }

    try {
      final product = await _productRepository.searchProductByBarcodeOrSku(foundCode);

      if (state.rapidScanModeEnabled) {
        // Rapid scan mode - emit events and continue scanning
        if (product != null) {
          if (product.isVariable) {
            _scannerNotificationController.add(
              ScannerNotification(
                "Producto variable. Use el modo normal para seleccionar opciones.",
                ScannerNotificationType.info,
              ),
            );
          } else if (!product.isAvailable) {
            _scannerNotificationController.add(
              ScannerNotification(
                "'${product.name}' está agotado.",
                ScannerNotificationType.error,
              ),
            );
          } else {
            _rapidScanProductController.add(product);
          }
        } else {
          _scannerNotificationController.add(
            ScannerNotification(
              "Producto con código '$foundCode' no encontrado.",
              ScannerNotificationType.error,
            ),
          );
        }

        // Delay before allowing next scan
        await Future.delayed(const Duration(milliseconds: 1200));
        state = state.copyWith(isProcessingBarcode: false);
      } else {
        // Normal mode - update state with product
        state = state.copyWith(
          scannedProduct: product,
          viewState: product != null
              ? ScannerViewState.productFound
              : ScannerViewState.noProduct,
          errorMessage: product == null
              ? "Producto no encontrado para el código '$foundCode'."
              : null,
          isProcessingBarcode: false, // ✅ FIX: Liberar bandera para permitir siguiente escaneo
        );
      }
    } catch (e) {
      if (state.rapidScanModeEnabled) {
        _scannerNotificationController.add(
          ScannerNotification(
            "Error: ${e.toString()}",
            ScannerNotificationType.error,
          ),
        );
      } else {
        state = state.copyWith(
          viewState: ScannerViewState.error,
          errorMessage: "Error al procesar código: ${e.toString()}",
        );
      }

      state = state.copyWith(isProcessingBarcode: false);
      debugPrint("[Scanner] Error processing barcode capture: $e");
    }
  }

  void onScannerError(MobileScannerException error) {
    state = state.copyWith(
      viewState: ScannerViewState.error,
      errorMessage: "Error de la cámara: ${error.errorDetails?.message ?? error.errorCode.name}",
      isCameraActive: false,
      isProcessingBarcode: false,
    );

    debugPrint("[Scanner] Scanner error: ${error.errorCode.name}");
  }

  // ========== SCANNER LIFECYCLE METHODS ==========

  Future<void> resumeScanning() async {
    debugPrint("[Scanner] resumeScanning() called - isCameraActive: ${state.isCameraActive}");

    state = state.copyWith(
      isProcessingBarcode: false,
      scannedProduct: null,
      errorMessage: null,
      latestBarcodeCapture: null,
    );

    // Only start scanner if camera is not already active
    if (!state.isCameraActive && !_isStartingCamera) {
      await startScanner();
      debugPrint("[Scanner] Scanning resumed - camera restarted");
    } else {
      debugPrint("[Scanner] resumeScanning() - camera already active, not restarting");
    }
  }

  Future<void> resetScanner({bool keepSearchResults = false}) async {
    debugPrint("[Scanner] resetScanner() called");

    state = state.copyWith(
      isProcessingBarcode: false,
      scannedProduct: null,
      errorMessage: null,
      isTorchOn: false,
      latestBarcodeCapture: null,
    );

    if (!keepSearchResults) {
      clearSearch();
    }

    await _stopCamera();
    debugPrint("[Scanner] Scanner reset complete");
  }

  /// Limpia el estado de producto encontrado SIN reiniciar la cámara
  /// Usado cuando el bottom sheet se cierra y queremos mantener la cámara activa
  void clearProductFoundState() {
    debugPrint("[Scanner] Clearing product found state (keeping camera active)");

    state = state.copyWith(
      viewState: ScannerViewState.scanning, // Volver a estado de escaneo
      isProcessingBarcode: false,
      scannedProduct: null,
      errorMessage: null,
      latestBarcodeCapture: null,
    );
    // ✅ NO se llama a _stopCamera() ni _startCamera()
    // La cámara permanece activa y lista para escanear
  }
}
