// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'order_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$CurrentOrderState {
  Order? get order => throw _privateConstructorUsedError;
  bool get isLoading => throw _privateConstructorUsedError;
  bool get isSaving => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;
  double get taxRate => throw _privateConstructorUsedError;
  bool get allowIndividualDiscounts => throw _privateConstructorUsedError;

  /// Create a copy of CurrentOrderState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CurrentOrderStateCopyWith<CurrentOrderState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CurrentOrderStateCopyWith<$Res> {
  factory $CurrentOrderStateCopyWith(
          CurrentOrderState value, $Res Function(CurrentOrderState) then) =
      _$CurrentOrderStateCopyWithImpl<$Res, CurrentOrderState>;
  @useResult
  $Res call(
      {Order? order,
      bool isLoading,
      bool isSaving,
      String? error,
      double taxRate,
      bool allowIndividualDiscounts});
}

/// @nodoc
class _$CurrentOrderStateCopyWithImpl<$Res, $Val extends CurrentOrderState>
    implements $CurrentOrderStateCopyWith<$Res> {
  _$CurrentOrderStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CurrentOrderState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? order = freezed,
    Object? isLoading = null,
    Object? isSaving = null,
    Object? error = freezed,
    Object? taxRate = null,
    Object? allowIndividualDiscounts = null,
  }) {
    return _then(_value.copyWith(
      order: freezed == order
          ? _value.order
          : order // ignore: cast_nullable_to_non_nullable
              as Order?,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      isSaving: null == isSaving
          ? _value.isSaving
          : isSaving // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
      taxRate: null == taxRate
          ? _value.taxRate
          : taxRate // ignore: cast_nullable_to_non_nullable
              as double,
      allowIndividualDiscounts: null == allowIndividualDiscounts
          ? _value.allowIndividualDiscounts
          : allowIndividualDiscounts // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CurrentOrderStateImplCopyWith<$Res>
    implements $CurrentOrderStateCopyWith<$Res> {
  factory _$$CurrentOrderStateImplCopyWith(_$CurrentOrderStateImpl value,
          $Res Function(_$CurrentOrderStateImpl) then) =
      __$$CurrentOrderStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {Order? order,
      bool isLoading,
      bool isSaving,
      String? error,
      double taxRate,
      bool allowIndividualDiscounts});
}

/// @nodoc
class __$$CurrentOrderStateImplCopyWithImpl<$Res>
    extends _$CurrentOrderStateCopyWithImpl<$Res, _$CurrentOrderStateImpl>
    implements _$$CurrentOrderStateImplCopyWith<$Res> {
  __$$CurrentOrderStateImplCopyWithImpl(_$CurrentOrderStateImpl _value,
      $Res Function(_$CurrentOrderStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of CurrentOrderState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? order = freezed,
    Object? isLoading = null,
    Object? isSaving = null,
    Object? error = freezed,
    Object? taxRate = null,
    Object? allowIndividualDiscounts = null,
  }) {
    return _then(_$CurrentOrderStateImpl(
      order: freezed == order
          ? _value.order
          : order // ignore: cast_nullable_to_non_nullable
              as Order?,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      isSaving: null == isSaving
          ? _value.isSaving
          : isSaving // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
      taxRate: null == taxRate
          ? _value.taxRate
          : taxRate // ignore: cast_nullable_to_non_nullable
              as double,
      allowIndividualDiscounts: null == allowIndividualDiscounts
          ? _value.allowIndividualDiscounts
          : allowIndividualDiscounts // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class _$CurrentOrderStateImpl extends _CurrentOrderState
    with DiagnosticableTreeMixin {
  const _$CurrentOrderStateImpl(
      {this.order,
      this.isLoading = false,
      this.isSaving = false,
      this.error,
      this.taxRate = 0.13,
      this.allowIndividualDiscounts = true})
      : super._();

  @override
  final Order? order;
  @override
  @JsonKey()
  final bool isLoading;
  @override
  @JsonKey()
  final bool isSaving;
  @override
  final String? error;
  @override
  @JsonKey()
  final double taxRate;
  @override
  @JsonKey()
  final bool allowIndividualDiscounts;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'CurrentOrderState(order: $order, isLoading: $isLoading, isSaving: $isSaving, error: $error, taxRate: $taxRate, allowIndividualDiscounts: $allowIndividualDiscounts)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'CurrentOrderState'))
      ..add(DiagnosticsProperty('order', order))
      ..add(DiagnosticsProperty('isLoading', isLoading))
      ..add(DiagnosticsProperty('isSaving', isSaving))
      ..add(DiagnosticsProperty('error', error))
      ..add(DiagnosticsProperty('taxRate', taxRate))
      ..add(DiagnosticsProperty(
          'allowIndividualDiscounts', allowIndividualDiscounts));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CurrentOrderStateImpl &&
            (identical(other.order, order) || other.order == order) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.isSaving, isSaving) ||
                other.isSaving == isSaving) &&
            (identical(other.error, error) || other.error == error) &&
            (identical(other.taxRate, taxRate) || other.taxRate == taxRate) &&
            (identical(
                    other.allowIndividualDiscounts, allowIndividualDiscounts) ||
                other.allowIndividualDiscounts == allowIndividualDiscounts));
  }

  @override
  int get hashCode => Object.hash(runtimeType, order, isLoading, isSaving,
      error, taxRate, allowIndividualDiscounts);

  /// Create a copy of CurrentOrderState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CurrentOrderStateImplCopyWith<_$CurrentOrderStateImpl> get copyWith =>
      __$$CurrentOrderStateImplCopyWithImpl<_$CurrentOrderStateImpl>(
          this, _$identity);
}

abstract class _CurrentOrderState extends CurrentOrderState {
  const factory _CurrentOrderState(
      {final Order? order,
      final bool isLoading,
      final bool isSaving,
      final String? error,
      final double taxRate,
      final bool allowIndividualDiscounts}) = _$CurrentOrderStateImpl;
  const _CurrentOrderState._() : super._();

  @override
  Order? get order;
  @override
  bool get isLoading;
  @override
  bool get isSaving;
  @override
  String? get error;
  @override
  double get taxRate;
  @override
  bool get allowIndividualDiscounts;

  /// Create a copy of CurrentOrderState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CurrentOrderStateImplCopyWith<_$CurrentOrderStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$OrderHistoryState {
  List<Order> get orders => throw _privateConstructorUsedError;
  int get currentPage => throw _privateConstructorUsedError;
  int get totalPages => throw _privateConstructorUsedError;
  bool get isLoading => throw _privateConstructorUsedError;
  bool get isLoadingMore => throw _privateConstructorUsedError;
  bool get canLoadMore => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;

  /// Create a copy of OrderHistoryState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OrderHistoryStateCopyWith<OrderHistoryState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OrderHistoryStateCopyWith<$Res> {
  factory $OrderHistoryStateCopyWith(
          OrderHistoryState value, $Res Function(OrderHistoryState) then) =
      _$OrderHistoryStateCopyWithImpl<$Res, OrderHistoryState>;
  @useResult
  $Res call(
      {List<Order> orders,
      int currentPage,
      int totalPages,
      bool isLoading,
      bool isLoadingMore,
      bool canLoadMore,
      String? error});
}

/// @nodoc
class _$OrderHistoryStateCopyWithImpl<$Res, $Val extends OrderHistoryState>
    implements $OrderHistoryStateCopyWith<$Res> {
  _$OrderHistoryStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OrderHistoryState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? orders = null,
    Object? currentPage = null,
    Object? totalPages = null,
    Object? isLoading = null,
    Object? isLoadingMore = null,
    Object? canLoadMore = null,
    Object? error = freezed,
  }) {
    return _then(_value.copyWith(
      orders: null == orders
          ? _value.orders
          : orders // ignore: cast_nullable_to_non_nullable
              as List<Order>,
      currentPage: null == currentPage
          ? _value.currentPage
          : currentPage // ignore: cast_nullable_to_non_nullable
              as int,
      totalPages: null == totalPages
          ? _value.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      isLoadingMore: null == isLoadingMore
          ? _value.isLoadingMore
          : isLoadingMore // ignore: cast_nullable_to_non_nullable
              as bool,
      canLoadMore: null == canLoadMore
          ? _value.canLoadMore
          : canLoadMore // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OrderHistoryStateImplCopyWith<$Res>
    implements $OrderHistoryStateCopyWith<$Res> {
  factory _$$OrderHistoryStateImplCopyWith(_$OrderHistoryStateImpl value,
          $Res Function(_$OrderHistoryStateImpl) then) =
      __$$OrderHistoryStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<Order> orders,
      int currentPage,
      int totalPages,
      bool isLoading,
      bool isLoadingMore,
      bool canLoadMore,
      String? error});
}

/// @nodoc
class __$$OrderHistoryStateImplCopyWithImpl<$Res>
    extends _$OrderHistoryStateCopyWithImpl<$Res, _$OrderHistoryStateImpl>
    implements _$$OrderHistoryStateImplCopyWith<$Res> {
  __$$OrderHistoryStateImplCopyWithImpl(_$OrderHistoryStateImpl _value,
      $Res Function(_$OrderHistoryStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of OrderHistoryState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? orders = null,
    Object? currentPage = null,
    Object? totalPages = null,
    Object? isLoading = null,
    Object? isLoadingMore = null,
    Object? canLoadMore = null,
    Object? error = freezed,
  }) {
    return _then(_$OrderHistoryStateImpl(
      orders: null == orders
          ? _value._orders
          : orders // ignore: cast_nullable_to_non_nullable
              as List<Order>,
      currentPage: null == currentPage
          ? _value.currentPage
          : currentPage // ignore: cast_nullable_to_non_nullable
              as int,
      totalPages: null == totalPages
          ? _value.totalPages
          : totalPages // ignore: cast_nullable_to_non_nullable
              as int,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      isLoadingMore: null == isLoadingMore
          ? _value.isLoadingMore
          : isLoadingMore // ignore: cast_nullable_to_non_nullable
              as bool,
      canLoadMore: null == canLoadMore
          ? _value.canLoadMore
          : canLoadMore // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$OrderHistoryStateImpl extends _OrderHistoryState
    with DiagnosticableTreeMixin {
  const _$OrderHistoryStateImpl(
      {final List<Order> orders = const [],
      this.currentPage = 1,
      this.totalPages = 1,
      this.isLoading = false,
      this.isLoadingMore = false,
      this.canLoadMore = true,
      this.error})
      : _orders = orders,
        super._();

  final List<Order> _orders;
  @override
  @JsonKey()
  List<Order> get orders {
    if (_orders is EqualUnmodifiableListView) return _orders;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_orders);
  }

  @override
  @JsonKey()
  final int currentPage;
  @override
  @JsonKey()
  final int totalPages;
  @override
  @JsonKey()
  final bool isLoading;
  @override
  @JsonKey()
  final bool isLoadingMore;
  @override
  @JsonKey()
  final bool canLoadMore;
  @override
  final String? error;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'OrderHistoryState(orders: $orders, currentPage: $currentPage, totalPages: $totalPages, isLoading: $isLoading, isLoadingMore: $isLoadingMore, canLoadMore: $canLoadMore, error: $error)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'OrderHistoryState'))
      ..add(DiagnosticsProperty('orders', orders))
      ..add(DiagnosticsProperty('currentPage', currentPage))
      ..add(DiagnosticsProperty('totalPages', totalPages))
      ..add(DiagnosticsProperty('isLoading', isLoading))
      ..add(DiagnosticsProperty('isLoadingMore', isLoadingMore))
      ..add(DiagnosticsProperty('canLoadMore', canLoadMore))
      ..add(DiagnosticsProperty('error', error));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderHistoryStateImpl &&
            const DeepCollectionEquality().equals(other._orders, _orders) &&
            (identical(other.currentPage, currentPage) ||
                other.currentPage == currentPage) &&
            (identical(other.totalPages, totalPages) ||
                other.totalPages == totalPages) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.isLoadingMore, isLoadingMore) ||
                other.isLoadingMore == isLoadingMore) &&
            (identical(other.canLoadMore, canLoadMore) ||
                other.canLoadMore == canLoadMore) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_orders),
      currentPage,
      totalPages,
      isLoading,
      isLoadingMore,
      canLoadMore,
      error);

  /// Create a copy of OrderHistoryState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderHistoryStateImplCopyWith<_$OrderHistoryStateImpl> get copyWith =>
      __$$OrderHistoryStateImplCopyWithImpl<_$OrderHistoryStateImpl>(
          this, _$identity);
}

abstract class _OrderHistoryState extends OrderHistoryState {
  const factory _OrderHistoryState(
      {final List<Order> orders,
      final int currentPage,
      final int totalPages,
      final bool isLoading,
      final bool isLoadingMore,
      final bool canLoadMore,
      final String? error}) = _$OrderHistoryStateImpl;
  const _OrderHistoryState._() : super._();

  @override
  List<Order> get orders;
  @override
  int get currentPage;
  @override
  int get totalPages;
  @override
  bool get isLoading;
  @override
  bool get isLoadingMore;
  @override
  bool get canLoadMore;
  @override
  String? get error;

  /// Create a copy of OrderHistoryState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderHistoryStateImplCopyWith<_$OrderHistoryStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$OrderSummary {
  double get subtotal => throw _privateConstructorUsedError;
  double get wcDiscount => throw _privateConstructorUsedError;
  double get manualDiscount => throw _privateConstructorUsedError;
  double get tax => throw _privateConstructorUsedError;
  double get total => throw _privateConstructorUsedError;
  double get taxRate => throw _privateConstructorUsedError;

  /// Create a copy of OrderSummary
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OrderSummaryCopyWith<OrderSummary> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OrderSummaryCopyWith<$Res> {
  factory $OrderSummaryCopyWith(
          OrderSummary value, $Res Function(OrderSummary) then) =
      _$OrderSummaryCopyWithImpl<$Res, OrderSummary>;
  @useResult
  $Res call(
      {double subtotal,
      double wcDiscount,
      double manualDiscount,
      double tax,
      double total,
      double taxRate});
}

/// @nodoc
class _$OrderSummaryCopyWithImpl<$Res, $Val extends OrderSummary>
    implements $OrderSummaryCopyWith<$Res> {
  _$OrderSummaryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OrderSummary
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? subtotal = null,
    Object? wcDiscount = null,
    Object? manualDiscount = null,
    Object? tax = null,
    Object? total = null,
    Object? taxRate = null,
  }) {
    return _then(_value.copyWith(
      subtotal: null == subtotal
          ? _value.subtotal
          : subtotal // ignore: cast_nullable_to_non_nullable
              as double,
      wcDiscount: null == wcDiscount
          ? _value.wcDiscount
          : wcDiscount // ignore: cast_nullable_to_non_nullable
              as double,
      manualDiscount: null == manualDiscount
          ? _value.manualDiscount
          : manualDiscount // ignore: cast_nullable_to_non_nullable
              as double,
      tax: null == tax
          ? _value.tax
          : tax // ignore: cast_nullable_to_non_nullable
              as double,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as double,
      taxRate: null == taxRate
          ? _value.taxRate
          : taxRate // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OrderSummaryImplCopyWith<$Res>
    implements $OrderSummaryCopyWith<$Res> {
  factory _$$OrderSummaryImplCopyWith(
          _$OrderSummaryImpl value, $Res Function(_$OrderSummaryImpl) then) =
      __$$OrderSummaryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double subtotal,
      double wcDiscount,
      double manualDiscount,
      double tax,
      double total,
      double taxRate});
}

/// @nodoc
class __$$OrderSummaryImplCopyWithImpl<$Res>
    extends _$OrderSummaryCopyWithImpl<$Res, _$OrderSummaryImpl>
    implements _$$OrderSummaryImplCopyWith<$Res> {
  __$$OrderSummaryImplCopyWithImpl(
      _$OrderSummaryImpl _value, $Res Function(_$OrderSummaryImpl) _then)
      : super(_value, _then);

  /// Create a copy of OrderSummary
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? subtotal = null,
    Object? wcDiscount = null,
    Object? manualDiscount = null,
    Object? tax = null,
    Object? total = null,
    Object? taxRate = null,
  }) {
    return _then(_$OrderSummaryImpl(
      subtotal: null == subtotal
          ? _value.subtotal
          : subtotal // ignore: cast_nullable_to_non_nullable
              as double,
      wcDiscount: null == wcDiscount
          ? _value.wcDiscount
          : wcDiscount // ignore: cast_nullable_to_non_nullable
              as double,
      manualDiscount: null == manualDiscount
          ? _value.manualDiscount
          : manualDiscount // ignore: cast_nullable_to_non_nullable
              as double,
      tax: null == tax
          ? _value.tax
          : tax // ignore: cast_nullable_to_non_nullable
              as double,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as double,
      taxRate: null == taxRate
          ? _value.taxRate
          : taxRate // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc

class _$OrderSummaryImpl extends _OrderSummary with DiagnosticableTreeMixin {
  const _$OrderSummaryImpl(
      {required this.subtotal,
      required this.wcDiscount,
      required this.manualDiscount,
      required this.tax,
      required this.total,
      required this.taxRate})
      : super._();

  @override
  final double subtotal;
  @override
  final double wcDiscount;
  @override
  final double manualDiscount;
  @override
  final double tax;
  @override
  final double total;
  @override
  final double taxRate;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'OrderSummary(subtotal: $subtotal, wcDiscount: $wcDiscount, manualDiscount: $manualDiscount, tax: $tax, total: $total, taxRate: $taxRate)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'OrderSummary'))
      ..add(DiagnosticsProperty('subtotal', subtotal))
      ..add(DiagnosticsProperty('wcDiscount', wcDiscount))
      ..add(DiagnosticsProperty('manualDiscount', manualDiscount))
      ..add(DiagnosticsProperty('tax', tax))
      ..add(DiagnosticsProperty('total', total))
      ..add(DiagnosticsProperty('taxRate', taxRate));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderSummaryImpl &&
            (identical(other.subtotal, subtotal) ||
                other.subtotal == subtotal) &&
            (identical(other.wcDiscount, wcDiscount) ||
                other.wcDiscount == wcDiscount) &&
            (identical(other.manualDiscount, manualDiscount) ||
                other.manualDiscount == manualDiscount) &&
            (identical(other.tax, tax) || other.tax == tax) &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.taxRate, taxRate) || other.taxRate == taxRate));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, subtotal, wcDiscount, manualDiscount, tax, total, taxRate);

  /// Create a copy of OrderSummary
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderSummaryImplCopyWith<_$OrderSummaryImpl> get copyWith =>
      __$$OrderSummaryImplCopyWithImpl<_$OrderSummaryImpl>(this, _$identity);
}

abstract class _OrderSummary extends OrderSummary {
  const factory _OrderSummary(
      {required final double subtotal,
      required final double wcDiscount,
      required final double manualDiscount,
      required final double tax,
      required final double total,
      required final double taxRate}) = _$OrderSummaryImpl;
  const _OrderSummary._() : super._();

  @override
  double get subtotal;
  @override
  double get wcDiscount;
  @override
  double get manualDiscount;
  @override
  double get tax;
  @override
  double get total;
  @override
  double get taxRate;

  /// Create a copy of OrderSummary
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderSummaryImplCopyWith<_$OrderSummaryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
