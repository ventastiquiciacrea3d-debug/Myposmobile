// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'scanner_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ScannerState {
  ScannerViewState get viewState => throw _privateConstructorUsedError;
  Product? get scannedProduct => throw _privateConstructorUsedError;
  String? get errorMessage => throw _privateConstructorUsedError;
  bool get isCameraActive => throw _privateConstructorUsedError;
  bool get isProcessingBarcode => throw _privateConstructorUsedError;
  bool get isTorchOn => throw _privateConstructorUsedError;
  bool get manualScanModeEnabled => throw _privateConstructorUsedError;
  bool get rapidScanModeEnabled => throw _privateConstructorUsedError;
  bool get isManualCaptureMode => throw _privateConstructorUsedError;
  BarcodeCapture? get latestBarcodeCapture =>
      throw _privateConstructorUsedError;
  List<Product> get searchResults => throw _privateConstructorUsedError;
  bool get isSearching => throw _privateConstructorUsedError;
  String? get searchErrorText => throw _privateConstructorUsedError;
  String get currentSearchQuery => throw _privateConstructorUsedError;
  int get currentPage => throw _privateConstructorUsedError;
  int get totalProducts => throw _privateConstructorUsedError;
  int get totalPages => throw _privateConstructorUsedError;
  bool get isLoadingMore => throw _privateConstructorUsedError;
  bool get canLoadMore => throw _privateConstructorUsedError;

  /// Create a copy of ScannerState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ScannerStateCopyWith<ScannerState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ScannerStateCopyWith<$Res> {
  factory $ScannerStateCopyWith(
          ScannerState value, $Res Function(ScannerState) then) =
      _$ScannerStateCopyWithImpl<$Res, ScannerState>;
  @useResult
  $Res call(
      {ScannerViewState viewState,
      Product? scannedProduct,
      String? errorMessage,
      bool isCameraActive,
      bool isProcessingBarcode,
      bool isTorchOn,
      bool manualScanModeEnabled,
      bool rapidScanModeEnabled,
      bool isManualCaptureMode,
      BarcodeCapture? latestBarcodeCapture,
      List<Product> searchResults,
      bool isSearching,
      String? searchErrorText,
      String currentSearchQuery,
      int currentPage,
      int totalProducts,
      int totalPages,
      bool isLoadingMore,
      bool canLoadMore});
}

/// @nodoc
class _$ScannerStateCopyWithImpl<$Res, $Val extends ScannerState>
    implements $ScannerStateCopyWith<$Res> {
  _$ScannerStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ScannerState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? viewState = null,
    Object? scannedProduct = freezed,
    Object? errorMessage = freezed,
    Object? isCameraActive = null,
    Object? isProcessingBarcode = null,
    Object? isTorchOn = null,
    Object? manualScanModeEnabled = null,
    Object? rapidScanModeEnabled = null,
    Object? isManualCaptureMode = null,
    Object? latestBarcodeCapture = freezed,
    Object? searchResults = null,
    Object? isSearching = null,
    Object? searchErrorText = freezed,
    Object? currentSearchQuery = null,
    Object? currentPage = null,
    Object? totalProducts = null,
    Object? totalPages = null,
    Object? isLoadingMore = null,
    Object? canLoadMore = null,
  }) {
    return _then(_value.copyWith(
      viewState: null == viewState
          ? _value.viewState
          : viewState // ignore: cast_nullable_to_non_nullable
              as ScannerViewState,
      scannedProduct: freezed == scannedProduct
          ? _value.scannedProduct
          : scannedProduct // ignore: cast_nullable_to_non_nullable
              as Product?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      isCameraActive: null == isCameraActive
          ? _value.isCameraActive
          : isCameraActive // ignore: cast_nullable_to_non_nullable
              as bool,
      isProcessingBarcode: null == isProcessingBarcode
          ? _value.isProcessingBarcode
          : isProcessingBarcode // ignore: cast_nullable_to_non_nullable
              as bool,
      isTorchOn: null == isTorchOn
          ? _value.isTorchOn
          : isTorchOn // ignore: cast_nullable_to_non_nullable
              as bool,
      manualScanModeEnabled: null == manualScanModeEnabled
          ? _value.manualScanModeEnabled
          : manualScanModeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      rapidScanModeEnabled: null == rapidScanModeEnabled
          ? _value.rapidScanModeEnabled
          : rapidScanModeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      isManualCaptureMode: null == isManualCaptureMode
          ? _value.isManualCaptureMode
          : isManualCaptureMode // ignore: cast_nullable_to_non_nullable
              as bool,
      latestBarcodeCapture: freezed == latestBarcodeCapture
          ? _value.latestBarcodeCapture
          : latestBarcodeCapture // ignore: cast_nullable_to_non_nullable
              as BarcodeCapture?,
      searchResults: null == searchResults
          ? _value.searchResults
          : searchResults // ignore: cast_nullable_to_non_nullable
              as List<Product>,
      isSearching: null == isSearching
          ? _value.isSearching
          : isSearching // ignore: cast_nullable_to_non_nullable
              as bool,
      searchErrorText: freezed == searchErrorText
          ? _value.searchErrorText
          : searchErrorText // ignore: cast_nullable_to_non_nullable
              as String?,
      currentSearchQuery: null == currentSearchQuery
          ? _value.currentSearchQuery
          : currentSearchQuery // ignore: cast_nullable_to_non_nullable
              as String,
      currentPage: null == currentPage
          ? _value.currentPage
          : currentPage // ignore: cast_nullable_to_non_nullable
              as int,
      totalProducts: null == totalProducts
          ? _value.totalProducts
          : totalProducts // ignore: cast_nullable_to_non_nullable
              as int,
      totalPages: null == totalPages
          ? _value.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int,
      isLoadingMore: null == isLoadingMore
          ? _value.isLoadingMore
          : isLoadingMore // ignore: cast_nullable_to_non_nullable
              as bool,
      canLoadMore: null == canLoadMore
          ? _value.canLoadMore
          : canLoadMore // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ScannerStateImplCopyWith<$Res>
    implements $ScannerStateCopyWith<$Res> {
  factory _$$ScannerStateImplCopyWith(
          _$ScannerStateImpl value, $Res Function(_$ScannerStateImpl) then) =
      __$$ScannerStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {ScannerViewState viewState,
      Product? scannedProduct,
      String? errorMessage,
      bool isCameraActive,
      bool isProcessingBarcode,
      bool isTorchOn,
      bool manualScanModeEnabled,
      bool rapidScanModeEnabled,
      bool isManualCaptureMode,
      BarcodeCapture? latestBarcodeCapture,
      List<Product> searchResults,
      bool isSearching,
      String? searchErrorText,
      String currentSearchQuery,
      int currentPage,
      int totalProducts,
      int totalPages,
      bool isLoadingMore,
      bool canLoadMore});
}

/// @nodoc
class __$$ScannerStateImplCopyWithImpl<$Res>
    extends _$ScannerStateCopyWithImpl<$Res, _$ScannerStateImpl>
    implements _$$ScannerStateImplCopyWith<$Res> {
  __$$ScannerStateImplCopyWithImpl(
      _$ScannerStateImpl _value, $Res Function(_$ScannerStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of ScannerState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? viewState = null,
    Object? scannedProduct = freezed,
    Object? errorMessage = freezed,
    Object? isCameraActive = null,
    Object? isProcessingBarcode = null,
    Object? isTorchOn = null,
    Object? manualScanModeEnabled = null,
    Object? rapidScanModeEnabled = null,
    Object? isManualCaptureMode = null,
    Object? latestBarcodeCapture = freezed,
    Object? searchResults = null,
    Object? isSearching = null,
    Object? searchErrorText = freezed,
    Object? currentSearchQuery = null,
    Object? currentPage = null,
    Object? totalProducts = null,
    Object? totalPages = null,
    Object? isLoadingMore = null,
    Object? canLoadMore = null,
  }) {
    return _then(_$ScannerStateImpl(
      viewState: null == viewState
          ? _value.viewState
          : viewState // ignore: cast_nullable_to_non_nullable
              as ScannerViewState,
      scannedProduct: freezed == scannedProduct
          ? _value.scannedProduct
          : scannedProduct // ignore: cast_nullable_to_non_nullable
              as Product?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      isCameraActive: null == isCameraActive
          ? _value.isCameraActive
          : isCameraActive // ignore: cast_nullable_to_non_nullable
              as bool,
      isProcessingBarcode: null == isProcessingBarcode
          ? _value.isProcessingBarcode
          : isProcessingBarcode // ignore: cast_nullable_to_non_nullable
              as bool,
      isTorchOn: null == isTorchOn
          ? _value.isTorchOn
          : isTorchOn // ignore: cast_nullable_to_non_nullable
              as bool,
      manualScanModeEnabled: null == manualScanModeEnabled
          ? _value.manualScanModeEnabled
          : manualScanModeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      rapidScanModeEnabled: null == rapidScanModeEnabled
          ? _value.rapidScanModeEnabled
          : rapidScanModeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      isManualCaptureMode: null == isManualCaptureMode
          ? _value.isManualCaptureMode
          : isManualCaptureMode // ignore: cast_nullable_to_non_nullable
              as bool,
      latestBarcodeCapture: freezed == latestBarcodeCapture
          ? _value.latestBarcodeCapture
          : latestBarcodeCapture // ignore: cast_nullable_to_non_nullable
              as BarcodeCapture?,
      searchResults: null == searchResults
          ? _value._searchResults
          : searchResults // ignore: cast_nullable_to_non_nullable
              as List<Product>,
      isSearching: null == isSearching
          ? _value.isSearching
          : isSearching // ignore: cast_nullable_to_non_nullable
              as bool,
      searchErrorText: freezed == searchErrorText
          ? _value.searchErrorText
          : searchErrorText // ignore: cast_nullable_to_non_nullable
              as String?,
      currentSearchQuery: null == currentSearchQuery
          ? _value.currentSearchQuery
          : currentSearchQuery // ignore: cast_nullable_to_non_nullable
              as String,
      currentPage: null == currentPage
          ? _value.currentPage
          : currentPage // ignore: cast_nullable_to_non_nullable
              as int,
      totalProducts: null == totalProducts
          ? _value.totalProducts
          : totalProducts // ignore: cast_nullable_to_non_nullable
              as int,
      totalPages: null == totalPages
          ? _value.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int,
      isLoadingMore: null == isLoadingMore
          ? _value.isLoadingMore
          : isLoadingMore // ignore: cast_nullable_to_non_nullable
              as bool,
      canLoadMore: null == canLoadMore
          ? _value.canLoadMore
          : canLoadMore // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class _$ScannerStateImpl extends _ScannerState with DiagnosticableTreeMixin {
  const _$ScannerStateImpl(
      {this.viewState = ScannerViewState.initial,
      this.scannedProduct,
      this.errorMessage,
      this.isCameraActive = false,
      this.isProcessingBarcode = false,
      this.isTorchOn = false,
      this.manualScanModeEnabled = false,
      this.rapidScanModeEnabled = false,
      this.isManualCaptureMode = false,
      this.latestBarcodeCapture,
      final List<Product> searchResults = const [],
      this.isSearching = false,
      this.searchErrorText,
      this.currentSearchQuery = '',
      this.currentPage = 1,
      this.totalProducts = 0,
      this.totalPages = 1,
      this.isLoadingMore = false,
      this.canLoadMore = false})
      : _searchResults = searchResults,
        super._();

  @override
  @JsonKey()
  final ScannerViewState viewState;
  @override
  final Product? scannedProduct;
  @override
  final String? errorMessage;
  @override
  @JsonKey()
  final bool isCameraActive;
  @override
  @JsonKey()
  final bool isProcessingBarcode;
  @override
  @JsonKey()
  final bool isTorchOn;
  @override
  @JsonKey()
  final bool manualScanModeEnabled;
  @override
  @JsonKey()
  final bool rapidScanModeEnabled;
  @override
  @JsonKey()
  final bool isManualCaptureMode;
  @override
  final BarcodeCapture? latestBarcodeCapture;
  final List<Product> _searchResults;
  @override
  @JsonKey()
  List<Product> get searchResults {
    if (_searchResults is EqualUnmodifiableListView) return _searchResults;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_searchResults);
  }

  @override
  @JsonKey()
  final bool isSearching;
  @override
  final String? searchErrorText;
  @override
  @JsonKey()
  final String currentSearchQuery;
  @override
  @JsonKey()
  final int currentPage;
  @override
  @JsonKey()
  final int totalProducts;
  @override
  @JsonKey()
  final int totalPages;
  @override
  @JsonKey()
  final bool isLoadingMore;
  @override
  @JsonKey()
  final bool canLoadMore;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'ScannerState(viewState: $viewState, scannedProduct: $scannedProduct, errorMessage: $errorMessage, isCameraActive: $isCameraActive, isProcessingBarcode: $isProcessingBarcode, isTorchOn: $isTorchOn, manualScanModeEnabled: $manualScanModeEnabled, rapidScanModeEnabled: $rapidScanModeEnabled, isManualCaptureMode: $isManualCaptureMode, latestBarcodeCapture: $latestBarcodeCapture, searchResults: $searchResults, isSearching: $isSearching, searchErrorText: $searchErrorText, currentSearchQuery: $currentSearchQuery, currentPage: $currentPage, totalProducts: $totalProducts, totalPages: $totalPages, isLoadingMore: $isLoadingMore, canLoadMore: $canLoadMore)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'ScannerState'))
      ..add(DiagnosticsProperty('viewState', viewState))
      ..add(DiagnosticsProperty('scannedProduct', scannedProduct))
      ..add(DiagnosticsProperty('errorMessage', errorMessage))
      ..add(DiagnosticsProperty('isCameraActive', isCameraActive))
      ..add(DiagnosticsProperty('isProcessingBarcode', isProcessingBarcode))
      ..add(DiagnosticsProperty('isTorchOn', isTorchOn))
      ..add(DiagnosticsProperty('manualScanModeEnabled', manualScanModeEnabled))
      ..add(DiagnosticsProperty('rapidScanModeEnabled', rapidScanModeEnabled))
      ..add(DiagnosticsProperty('isManualCaptureMode', isManualCaptureMode))
      ..add(DiagnosticsProperty('latestBarcodeCapture', latestBarcodeCapture))
      ..add(DiagnosticsProperty('searchResults', searchResults))
      ..add(DiagnosticsProperty('isSearching', isSearching))
      ..add(DiagnosticsProperty('searchErrorText', searchErrorText))
      ..add(DiagnosticsProperty('currentSearchQuery', currentSearchQuery))
      ..add(DiagnosticsProperty('currentPage', currentPage))
      ..add(DiagnosticsProperty('totalProducts', totalProducts))
      ..add(DiagnosticsProperty('totalPages', totalPages))
      ..add(DiagnosticsProperty('isLoadingMore', isLoadingMore))
      ..add(DiagnosticsProperty('canLoadMore', canLoadMore));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ScannerStateImpl &&
            (identical(other.viewState, viewState) ||
                other.viewState == viewState) &&
            (identical(other.scannedProduct, scannedProduct) ||
                other.scannedProduct == scannedProduct) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.isCameraActive, isCameraActive) ||
                other.isCameraActive == isCameraActive) &&
            (identical(other.isProcessingBarcode, isProcessingBarcode) ||
                other.isProcessingBarcode == isProcessingBarcode) &&
            (identical(other.isTorchOn, isTorchOn) ||
                other.isTorchOn == isTorchOn) &&
            (identical(other.manualScanModeEnabled, manualScanModeEnabled) ||
                other.manualScanModeEnabled == manualScanModeEnabled) &&
            (identical(other.rapidScanModeEnabled, rapidScanModeEnabled) ||
                other.rapidScanModeEnabled == rapidScanModeEnabled) &&
            (identical(other.isManualCaptureMode, isManualCaptureMode) ||
                other.isManualCaptureMode == isManualCaptureMode) &&
            (identical(other.latestBarcodeCapture, latestBarcodeCapture) ||
                other.latestBarcodeCapture == latestBarcodeCapture) &&
            const DeepCollectionEquality()
                .equals(other._searchResults, _searchResults) &&
            (identical(other.isSearching, isSearching) ||
                other.isSearching == isSearching) &&
            (identical(other.searchErrorText, searchErrorText) ||
                other.searchErrorText == searchErrorText) &&
            (identical(other.currentSearchQuery, currentSearchQuery) ||
                other.currentSearchQuery == currentSearchQuery) &&
            (identical(other.currentPage, currentPage) ||
                other.currentPage == currentPage) &&
            (identical(other.totalProducts, totalProducts) ||
                other.totalProducts == totalProducts) &&
            (identical(other.totalPages, totalPages) ||
                other.totalPages == totalPages) &&
            (identical(other.isLoadingMore, isLoadingMore) ||
                other.isLoadingMore == isLoadingMore) &&
            (identical(other.canLoadMore, canLoadMore) ||
                other.canLoadMore == canLoadMore));
  }

  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        viewState,
        scannedProduct,
        errorMessage,
        isCameraActive,
        isProcessingBarcode,
        isTorchOn,
        manualScanModeEnabled,
        rapidScanModeEnabled,
        isManualCaptureMode,
        latestBarcodeCapture,
        const DeepCollectionEquality().hash(_searchResults),
        isSearching,
        searchErrorText,
        currentSearchQuery,
        currentPage,
        totalProducts,
        totalPages,
        isLoadingMore,
        canLoadMore
      ]);

  /// Create a copy of ScannerState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ScannerStateImplCopyWith<_$ScannerStateImpl> get copyWith =>
      __$$ScannerStateImplCopyWithImpl<_$ScannerStateImpl>(this, _$identity);
}

abstract class _ScannerState extends ScannerState {
  const factory _ScannerState(
      {final ScannerViewState viewState,
      final Product? scannedProduct,
      final String? errorMessage,
      final bool isCameraActive,
      final bool isProcessingBarcode,
      final bool isTorchOn,
      final bool manualScanModeEnabled,
      final bool rapidScanModeEnabled,
      final bool isManualCaptureMode,
      final BarcodeCapture? latestBarcodeCapture,
      final List<Product> searchResults,
      final bool isSearching,
      final String? searchErrorText,
      final String currentSearchQuery,
      final int currentPage,
      final int totalProducts,
      final int totalPages,
      final bool isLoadingMore,
      final bool canLoadMore}) = _$ScannerStateImpl;
  const _ScannerState._() : super._();

  @override
  ScannerViewState get viewState;
  @override
  Product? get scannedProduct;
  @override
  String? get errorMessage;
  @override
  bool get isCameraActive;
  @override
  bool get isProcessingBarcode;
  @override
  bool get isTorchOn;
  @override
  bool get manualScanModeEnabled;
  @override
  bool get rapidScanModeEnabled;
  @override
  bool get isManualCaptureMode;
  @override
  BarcodeCapture? get latestBarcodeCapture;
  @override
  List<Product> get searchResults;
  @override
  bool get isSearching;
  @override
  String? get searchErrorText;
  @override
  String get currentSearchQuery;
  @override
  int get currentPage;
  @override
  int get totalProducts;
  @override
  int get totalPages;
  @override
  bool get isLoadingMore;
  @override
  bool get canLoadMore;

  /// Create a copy of ScannerState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ScannerStateImplCopyWith<_$ScannerStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
