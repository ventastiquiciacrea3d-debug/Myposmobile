// lib/services/scanner_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScannerServiceStatus {
  ready,
  scanning,
  detected,
  error,
}

/// ✅ MEJORA: Modos de enfoque disponibles
enum FocusMode {
  auto,       // Enfoque automático (por defecto)
  continuous, // Enfoque continuo
  fixed,      // Enfoque fijo (sin autofocus)
}

/// ✅ CONSTANTES PARA PREFERENCIAS
const String kScannerZoomLevelKey = 'scanner_zoom_level';
const String kScannerFocusModeKey = 'scanner_focus_mode';
const String kScannerFixedZoomKey = 'scanner_fixed_zoom_enabled';

class ScannerService {
  MobileScannerController? _controller;

  // ✅ MEJORA: Configuraciones de cámara
  double _zoomLevel = 0.0;           // 0.0 = sin zoom, 1.0 = zoom máximo
  FocusMode _focusMode = FocusMode.auto;
  bool _useFixedZoom = false;        // Si true, aplica zoom fijo al iniciar
  double _fixedZoomValue = 0.3;      // Valor de zoom fijo (30% por defecto)

  // ✅ Getters para el estado actual
  double get zoomLevel => _zoomLevel;
  FocusMode get focusMode => _focusMode;
  bool get useFixedZoom => _useFixedZoom;
  double get fixedZoomValue => _fixedZoomValue;

  MobileScannerController get controller {
    _controller ??= MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      returnImage: false,
      detectionTimeoutMs: 250,
      // ✅ NOTA: mobile_scanner 7.x no tiene parámetro directo de autofocus
      // El control se hace mediante zoom y la API de la cámara nativa
    );
    return _controller!;
  }

  ValueNotifier<ScannerServiceStatus> scannerStatus = ValueNotifier<ScannerServiceStatus>(ScannerServiceStatus.ready);
  String? _lastScannedCode;
  String? get lastScannedCode => _lastScannedCode;

  final StreamController<String> _barcodeStreamController = StreamController<String>.broadcast();
  Stream<String> get onBarcodeDetected => _barcodeStreamController.stream;

  ScannerService() {
    debugPrint("[ScannerService] Initialized.");
    _loadSavedSettings();
  }

  /// ✅ MEJORA: Cargar configuraciones guardadas
  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _zoomLevel = prefs.getDouble(kScannerZoomLevelKey) ?? 0.0;
      _useFixedZoom = prefs.getBool(kScannerFixedZoomKey) ?? false;
      _fixedZoomValue = prefs.getDouble('scanner_fixed_zoom_value') ?? 0.3;

      final savedFocusMode = prefs.getInt(kScannerFocusModeKey) ?? 0;
      _focusMode = FocusMode.values[savedFocusMode.clamp(0, FocusMode.values.length - 1)];

      debugPrint("[ScannerService] Settings loaded: zoom=$_zoomLevel, fixedZoom=$_useFixedZoom, fixedValue=$_fixedZoomValue, focusMode=$_focusMode");
    } catch (e) {
      debugPrint("[ScannerService] Error loading settings: $e");
    }
  }

  /// ✅ MEJORA: Guardar configuraciones
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kScannerZoomLevelKey, _zoomLevel);
      await prefs.setBool(kScannerFixedZoomKey, _useFixedZoom);
      await prefs.setDouble('scanner_fixed_zoom_value', _fixedZoomValue);
      await prefs.setInt(kScannerFocusModeKey, _focusMode.index);
      debugPrint("[ScannerService] Settings saved.");
    } catch (e) {
      debugPrint("[ScannerService] Error saving settings: $e");
    }
  }

  Future<void> startScanner() async {
    debugPrint("[ScannerService] Starting scanner...");
    try {
      if (!controller.value.isInitialized || !controller.value.isRunning) {
        await controller.start();
      }

      // ✅ MEJORA: Aplicar zoom fijo si está habilitado
      if (_useFixedZoom) {
        await Future.delayed(const Duration(milliseconds: 300)); // Esperar inicialización
        await setZoomLevel(_fixedZoomValue);
        debugPrint("[ScannerService] Applied fixed zoom: $_fixedZoomValue");
      } else if (_zoomLevel > 0) {
        // Restaurar último zoom usado
        await Future.delayed(const Duration(milliseconds: 300));
        await setZoomLevel(_zoomLevel);
      }

      scannerStatus.value = ScannerServiceStatus.scanning;
    } catch (e) {
      debugPrint("[ScannerService] Error starting scanner: $e");
      scannerStatus.value = ScannerServiceStatus.error;
      rethrow;
    }
  }

  Future<void> stopScanner() async {
    debugPrint("[ScannerService] Stopping scanner analysis...");
    if (_controller == null || !_controller!.value.isRunning) {
      debugPrint("...Controller already stopped or null. Nothing to do.");
      return;
    }
    try {
      await _controller!.stop();
      scannerStatus.value = ScannerServiceStatus.ready;
      debugPrint("...Scanner analysis stopped successfully.");
    } catch (e) {
      debugPrint("[ScannerService] Error stopping scanner analysis: $e");
      scannerStatus.value = ScannerServiceStatus.error;
    }
  }

  Future<void> toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      debugPrint("[ScannerService] Torch toggle attempted but controller not ready.");
      return;
    }
    try {
      await controller.toggleTorch();
      debugPrint("[ScannerService] Torch toggled.");
    } catch (e) {
      debugPrint("[ScannerService] Error toggling torch: $e");
    }
  }

  /// ✅ MEJORA: Establecer nivel de zoom (0.0 a 1.0)
  Future<void> setZoomLevel(double level) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      debugPrint("[ScannerService] Zoom attempted but controller not ready.");
      return;
    }

    try {
      // Clamp entre 0.0 y 1.0
      final clampedLevel = level.clamp(0.0, 1.0);
      await _controller!.setZoomScale(clampedLevel);
      _zoomLevel = clampedLevel;
      debugPrint("[ScannerService] Zoom set to: $clampedLevel");
    } catch (e) {
      debugPrint("[ScannerService] Error setting zoom: $e");
    }
  }

  /// ✅ MEJORA: Incrementar zoom
  Future<void> zoomIn({double step = 0.1}) async {
    await setZoomLevel(_zoomLevel + step);
  }

  /// ✅ MEJORA: Decrementar zoom
  Future<void> zoomOut({double step = 0.1}) async {
    await setZoomLevel(_zoomLevel - step);
  }

  /// ✅ MEJORA: Resetear zoom a 0
  Future<void> resetZoom() async {
    await setZoomLevel(0.0);
  }

  /// ✅ MEJORA: Configurar modo de enfoque fijo
  Future<void> setFixedZoomMode({required bool enabled, double? zoomValue}) async {
    _useFixedZoom = enabled;
    if (zoomValue != null) {
      _fixedZoomValue = zoomValue.clamp(0.0, 1.0);
    }

    await _saveSettings();

    // Si está activo el scanner, aplicar inmediatamente
    if (enabled && _controller != null && _controller!.value.isRunning) {
      await setZoomLevel(_fixedZoomValue);
    }

    debugPrint("[ScannerService] Fixed zoom mode: $enabled, value: $_fixedZoomValue");
  }

  /// ✅ MEJORA: Establecer valor de zoom fijo
  Future<void> setFixedZoomValue(double value) async {
    _fixedZoomValue = value.clamp(0.0, 1.0);
    await _saveSettings();

    // Si zoom fijo está habilitado, aplicar inmediatamente
    if (_useFixedZoom && _controller != null && _controller!.value.isRunning) {
      await setZoomLevel(_fixedZoomValue);
    }

    debugPrint("[ScannerService] Fixed zoom value set to: $_fixedZoomValue");
  }

  /// ✅ MEJORA: Presets de distancia focal para diferentes casos de uso
  Future<void> applyFocusPreset(String preset) async {
    double zoomValue;

    switch (preset) {
      case 'close':
        // Para códigos muy cercanos (< 10cm) - etiquetas pequeñas
        zoomValue = 0.0;
        break;
      case 'medium':
        // Para distancia media (10-30cm) - productos en estante
        zoomValue = 0.3;
        break;
      case 'far':
        // Para distancia lejana (30-50cm) - cajas grandes
        zoomValue = 0.5;
        break;
      case 'very_far':
        // Para distancia muy lejana (> 50cm)
        zoomValue = 0.7;
        break;
      default:
        zoomValue = 0.3; // Default medio
    }

    await setFixedZoomMode(enabled: true, zoomValue: zoomValue);
    debugPrint("[ScannerService] Applied focus preset: $preset (zoom: $zoomValue)");
  }

  void onBarcodeCapture(BarcodeCapture capture) {
    if (scannerStatus.value != ScannerServiceStatus.scanning) return;

    final String? code = capture.barcodes.firstWhereOrNull((b) => b.rawValue != null && b.rawValue!.isNotEmpty)?.rawValue;
    if (code != null && code.isNotEmpty) {
      scannerStatus.value = ScannerServiceStatus.detected;
      _lastScannedCode = code;
      if (!_barcodeStreamController.isClosed) {
        _barcodeStreamController.add(code);
        debugPrint("[ScannerService] Barcode detected and emitted: $code");
      }
    }
  }

  void onScannerWidgetError(MobileScannerException error) {
    scannerStatus.value = ScannerServiceStatus.error;
    debugPrint('[ScannerService] MobileScanner Widget Error: Code: ${error.errorCode}, Message: ${error.errorDetails?.message ?? 'N/A'}');
  }

  void dispose() {
    debugPrint("[ScannerService] dispose() called.");
    _controller?.dispose();
    _controller = null;
    _barcodeStreamController.close();
    scannerStatus.dispose();
    debugPrint("[ScannerService] Disposed.");
  }
}
