// lib/services/scanner_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:collection/collection.dart';

enum ScannerServiceStatus {
  ready,
  scanning,
  detected,
  error,
}

class ScannerService {
  MobileScannerController? _controller;

  MobileScannerController get controller {
    _controller ??= MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back
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
  }

  Future<void> startScanner() async {
    debugPrint("[ScannerService] Starting scanner...");
    try {
      if (!controller.value.isInitialized || !controller.value.isRunning) {
        await controller.start();
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