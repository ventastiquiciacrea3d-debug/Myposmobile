// lib/providers/scanner_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/product.dart';

part 'scanner_state.freezed.dart';

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

/// ✓ FASE 2 RIVERPOD: Estado inmutable para Scanner
@freezed
class ScannerState with _$ScannerState {
  const factory ScannerState({
    @Default(ScannerViewState.initial) ScannerViewState viewState,
    Product? scannedProduct,
    String? errorMessage,
    @Default(false) bool isCameraActive,
    @Default(false) bool isProcessingBarcode,
    @Default(false) bool isTorchOn,
    @Default(false) bool manualScanModeEnabled,
    @Default(false) bool rapidScanModeEnabled,
    @Default(false) bool isManualCaptureMode,
    BarcodeCapture? latestBarcodeCapture,
    @Default([]) List<Product> searchResults,
    @Default(false) bool isSearching,
    String? searchErrorText,
    @Default('') String currentSearchQuery,
    @Default(1) int currentPage,
    @Default(0) int totalProducts,
    @Default(1) int totalPages,
    @Default(false) bool isLoadingMore,
    @Default(false) bool canLoadMore,
  }) = _ScannerState;

  const ScannerState._();

  factory ScannerState.initial() => const ScannerState();
}
