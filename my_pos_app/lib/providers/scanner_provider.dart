// lib/providers/scanner_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../models/product.dart';
import '../services/scanner_service.dart';
import '../repositories/product_repository.dart';
import '../config/constants.dart';
import '../locator.dart';

enum ScannerNotificationType { success, info, error }

class ScannerNotification {
  final String message;
  final ScannerNotificationType type;
  ScannerNotification(this.message, this.type);
}

enum ScannerViewState {
  initial,
  awaitingActivation,
  scanning,
  processing,
  productFound,
  noProduct,
  error
}

class ScannerProvider extends ChangeNotifier {
  final ScannerService _scannerService = getIt<ScannerService>();
  final ProductRepository _productRepository = getIt<ProductRepository>();
  final SharedPreferences sharedPreferences;

  ScannerViewState _state = ScannerViewState.initial;
  Product? _scannedProduct;
  String? _errorMessage;
  bool _isCameraActive = false;
  bool _isStartingCamera = false;
  bool _isProcessingBarcode = false;
  bool _isTorchOn = false;

  bool _manualScanModeEnabled = false;
  bool _rapidScanModeEnabled = false;
  bool _isManualCaptureMode = false;
  BarcodeCapture? _latestBarcodeCapture;

  final StreamController<Product> _rapidScanProductController = StreamController.broadcast();
  Stream<Product> get onRapidScanSuccess => _rapidScanProductController.stream;

  final StreamController<ScannerNotification> _scannerNotificationController = StreamController.broadcast();
  Stream<ScannerNotification> get onScannerNotification => _scannerNotificationController.stream;

  List<Product> _searchResults = [];
  bool _isSearching = false;
  String? _searchErrorText;
  String _currentSearchQuery = '';

  int _currentPage = 1;
  int _totalProducts = 0;
  int _totalPages = 1;
  bool _isLoadingMore = false;
  bool _canLoadMore = false;
  static const int _productsPerPage = 20;

  StreamSubscription? _productUpdateSubscription;
  bool _isDisposed = false;

  ScannerViewState get state => _state;
  Product? get scannedProduct => _scannedProduct;
  String? get errorMessage => _errorMessage;
  bool get isCameraActive => _isCameraActive;
  bool get rapidScanModeEnabled => _rapidScanModeEnabled;
  bool get isManualCaptureMode => _isManualCaptureMode;
  bool get isTorchOn => _isTorchOn;
  ScannerService get scannerService => _scannerService;
  List<Product> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchErrorText => _searchErrorText;
  bool get isDisposed => _isDisposed;
  int get currentPage => _currentPage;
  int get totalProducts => _totalProducts;
  int get totalPages => _totalPages;
  bool get isLoadingMore => _isLoadingMore;
  bool get canLoadMore => _canLoadMore;


  ScannerProvider({ required this.sharedPreferences, }) {
    debugPrint("[ScannerProvider] Constructor called.");
    _loadSettings();
    _listenToProductUpdatesFromRepository();
  }

  Future<void> performSearch(String query) async {
    if (_isDisposed) return;
    final trimmedQuery = query.trim();
    if (_currentSearchQuery == trimmedQuery && _isSearching) return;

    _currentSearchQuery = trimmedQuery;
    if (trimmedQuery.length < 2) {
      clearSearch();
      return;
    }

    _currentPage = 1;
    _searchResults = [];
    _isSearching = true;
    _searchErrorText = null;
    notifyListeners();

    try {
      final apiResponse = await _productRepository.searchProductsByTerm(
        trimmedQuery,
        page: _currentPage,
        limit: _productsPerPage,
        onCachedResults: (cachedResults) {
          if (_isDisposed || _currentSearchQuery != trimmedQuery) return;
          _searchResults = cachedResults;
          _isSearching = true;
          _canLoadMore = false;
          notifyListeners();
        },
      );

      if (_isDisposed || _currentSearchQuery != trimmedQuery) return;

      _searchResults = (apiResponse['products'] as List?)?.cast<Product>() ?? [];
      _totalProducts = apiResponse['total_products'] as int? ?? 0;
      _totalPages = apiResponse['total_pages'] as int? ?? 1;
      _canLoadMore = _currentPage < _totalPages;
      _searchErrorText = _searchResults.isEmpty ? "No se encontraron productos para: '$trimmedQuery'" : null;

    } catch (e) {
      if(_isDisposed || _currentSearchQuery != trimmedQuery) return;
      _searchErrorText = 'Error: ${e.toString()}.';
    } finally {
      if (!_isDisposed && _currentSearchQuery == trimmedQuery) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  void _loadSettings() {
    if (_isDisposed) return;
    try {
      _manualScanModeEnabled = sharedPreferences.getBool(manualScanModePrefKey) ?? false;
      _rapidScanModeEnabled = sharedPreferences.getBool(rapidScanModePrefKey) ?? false;
    } catch (e) { /* default to false */ }
  }

  void setManualCaptureMode(bool enabled) {
    if (_isDisposed || _isManualCaptureMode == enabled) return;
    _isManualCaptureMode = enabled;
    _latestBarcodeCapture = null;
    notifyListeners();
  }

  Future<void> _startCamera() async {
    if (_isDisposed || _isCameraActive || _isStartingCamera) return;
    _isStartingCamera = true;
    _state = ScannerViewState.scanning;
    if (!_isDisposed) notifyListeners();
    try {
      await _scannerService.startScanner();
      _isCameraActive = true;
    } catch (e) {
      if (!_isDisposed) {
        _state = ScannerViewState.error;
        _errorMessage = "Error al iniciar la cámara: ${e.toString()}";
        _isCameraActive = false;
        notifyListeners();
      }
    } finally {
      if (!_isDisposed) _isStartingCamera = false;
    }
  }

  Future<void> _stopCamera() async {
    if (_isDisposed || !_isCameraActive) return;
    try {
      await _scannerService.stopScanner();
    } catch (e) {
      debugPrint("Error stopping camera: ${e.toString()}");
    } finally {
      if(!_isDisposed) {
        _isCameraActive = false;
        _isTorchOn = false;
        _state = _manualScanModeEnabled ? ScannerViewState.awaitingActivation : ScannerViewState.initial;
        notifyListeners();
      }
    }
  }

  void _listenToProductUpdatesFromRepository() {
    _productUpdateSubscription?.cancel();
    if (_isDisposed) return;
    _productUpdateSubscription = _productRepository.onProductUpdatedFromApi.listen(
          (updatedProductFull) {
        if(_isDisposed) return;
        if (_scannedProduct?.id == updatedProductFull.id) _scannedProduct = updatedProductFull;
        final index = _searchResults.indexWhere((p) => p.id == updatedProductFull.id);
        if (index != -1) {
          _searchResults[index] = updatedProductFull;
          if (!_isDisposed) notifyListeners();
        }
      },
    );
  }

  Future<void> startScanner() async {
    if (_isDisposed) return;
    _loadSettings();
    if (_manualScanModeEnabled) {
      if (_state != ScannerViewState.awaitingActivation) {
        _state = ScannerViewState.awaitingActivation;
        if (!_isDisposed) notifyListeners();
      }
    } else {
      await _startCamera();
    }
  }

  Future<void> activateManualScan() async {
    if (_isDisposed) return;
    if (_manualScanModeEnabled && !_isCameraActive) {
      await _startCamera();
    }
  }

  Future<void> toggleTorch() async {
    if (_isDisposed) return;
    try {
      await _scannerService.toggleTorch();
      _isTorchOn = !_isTorchOn;
      if (!_isDisposed) notifyListeners();
    } catch (e) {
      debugPrint("Error toggling torch in provider: $e");
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (_isDisposed) return;
    _state = ScannerViewState.processing;
    _errorMessage = null;
    _scannedProduct = null;
    if (!_isDisposed) notifyListeners();
    try {
      final product = await _productRepository.searchProductByBarcodeOrSku(barcode);
      if (_isDisposed) return;
      if (product == null) {
        _state = ScannerViewState.noProduct;
        _errorMessage = "Producto no encontrado para el código '$barcode'.";
      } else {
        _scannedProduct = product;
        _state = ScannerViewState.productFound;
        _errorMessage = null;
      }
    } catch (e) {
      if(_isDisposed) return;
      _state = ScannerViewState.error;
      _errorMessage = "Ocurrió un error: ${e.toString()}";
    } finally {
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> loadMoreSearchResults() async {
    if (_isDisposed || _isLoadingMore || !_canLoadMore || _currentSearchQuery.isEmpty) return;
    _isLoadingMore = true;
    _currentPage++;
    if (!_isDisposed) notifyListeners();
    try {
      final apiResponse = await _productRepository.searchProductsByTerm(_currentSearchQuery, page: _currentPage, limit: _productsPerPage);
      if (_isDisposed || _currentSearchQuery != (apiResponse['query'] ?? '')) return;
      final newApiProducts = (apiResponse['products'] as List?)?.cast<Product>() ?? [];
      if (newApiProducts.isNotEmpty) _searchResults.addAll(newApiProducts);
      _totalProducts = apiResponse['total_products'] as int? ?? _searchResults.length;
      _totalPages = apiResponse['total_pages'] as int? ?? 1;
      _canLoadMore = _currentPage < _totalPages;
    } catch (e) {
      if(_isDisposed) return;
      _searchErrorText = "Error al cargar más: ${e.toString()}.";
      _canLoadMore = false;
    } finally {
      if (!_isDisposed) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    if (_isDisposed) return;
    if (_currentSearchQuery.isNotEmpty || _searchResults.isNotEmpty || _isSearching || _searchErrorText != null || _totalProducts > 0) {
      _currentSearchQuery = '';
      _searchResults = [];
      _isSearching = false;
      _searchErrorText = null;
      _currentPage = 1;
      _totalProducts = 0;
      _totalPages = 1;
      _canLoadMore = false;
      _isLoadingMore = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> resumeScanning() async {
    if (_isDisposed) return;
    _isProcessingBarcode = false;
    _scannedProduct = null;
    _errorMessage = null;
    _latestBarcodeCapture = null;
    await startScanner();
  }

  Future<void> resetScanner({bool keepSearchResults = false}) async {
    if (_isDisposed) return;
    _isProcessingBarcode = false;
    _scannedProduct = null;
    _errorMessage = null;
    _isTorchOn = false;
    _latestBarcodeCapture = null;
    if (!keepSearchResults) clearSearch();
    await _stopCamera();
  }

  void handleBarcodeDetection(BarcodeCapture capture) {
    if (_isDisposed || state != ScannerViewState.scanning) return;
    if (_isManualCaptureMode) {
      _latestBarcodeCapture = capture;
    } else {
      _processBarcodeCapture(capture);
    }
  }

  Future<void> triggerManualCapture() async {
    if (_latestBarcodeCapture != null) {
      await _processBarcodeCapture(_latestBarcodeCapture!);
      _latestBarcodeCapture = null;
    }
  }

  Future<void> _processBarcodeCapture(BarcodeCapture capture) async {
    if (_isDisposed || _isProcessingBarcode || state != ScannerViewState.scanning) return;

    final String? foundCode = capture.barcodes.firstWhereOrNull((b) => b.rawValue != null && b.rawValue!.isNotEmpty)?.rawValue;
    if (foundCode == null) return;

    _isProcessingBarcode = true;
    if (!_isDisposed) notifyListeners();

    if (!_rapidScanModeEnabled) {
      await _scannerService.stopScanner();
      if (!_isDisposed) {
        _isCameraActive = false;
        notifyListeners();
      }
    }

    try {
      final product = await _productRepository.searchProductByBarcodeOrSku(foundCode);
      if (_isDisposed) return;

      if (_rapidScanModeEnabled) {
        if (product != null) {
          if (product.isVariable) {
            _scannerNotificationController.add(ScannerNotification("Producto variable. Use el modo normal para seleccionar opciones.", ScannerNotificationType.info));
          } else if (!product.isAvailable) {
            _scannerNotificationController.add(ScannerNotification("'${product.name}' está agotado.", ScannerNotificationType.error));
          } else {
            _rapidScanProductController.add(product);
          }
        } else {
          _scannerNotificationController.add(ScannerNotification("Producto con código '$foundCode' no encontrado.", ScannerNotificationType.error));
        }
        await Future.delayed(const Duration(milliseconds: 1200));
        _isProcessingBarcode = false;
        if (!_isDisposed) notifyListeners();
      } else {
        _scannedProduct = product;
        _state = product != null ? ScannerViewState.productFound : ScannerViewState.noProduct;
        if (product == null) _errorMessage = "Producto no encontrado para el código '$foundCode'.";
        if (!_isDisposed) notifyListeners();
      }
    } catch(e) {
      if (_rapidScanModeEnabled) {
        _scannerNotificationController.add(ScannerNotification("Error: ${e.toString()}", ScannerNotificationType.error));
      } else {
        _state = ScannerViewState.error;
        _errorMessage = "Error al procesar código: ${e.toString()}";
      }
      if (!_isDisposed) {
        _isProcessingBarcode = false;
        notifyListeners();
      }
    }
  }

  void onScannerError(MobileScannerException error) {
    if (_isDisposed) return;
    _state = ScannerViewState.error;
    _errorMessage = "Error de la cámara: ${error.errorDetails?.message ?? error.errorCode.name}";
    _isCameraActive = false;
    _isProcessingBarcode = false;
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    debugPrint("[ScannerProvider] dispose() called.");
    _isDisposed = true;
    _productUpdateSubscription?.cancel();
    _rapidScanProductController.close();
    _scannerNotificationController.close();
    _scannerService.dispose();
    super.dispose();
  }
}