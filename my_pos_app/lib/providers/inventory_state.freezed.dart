// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inventory_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$InventoryState {
// Inventory movements (history) with pagination
  List<InventoryMovement> get inventoryMovements =>
      throw _privateConstructorUsedError;
  int get movementsCurrentPage => throw _privateConstructorUsedError;
  bool get movementsIsLoading => throw _privateConstructorUsedError;
  bool get movementsIsLoadingMore => throw _privateConstructorUsedError;
  bool get movementsCanLoadMore => throw _privateConstructorUsedError;
  String? get movementsError => throw _privateConstructorUsedError;
  int get movementsTotalPages =>
      throw _privateConstructorUsedError; // Inventory products management
  List<Product> get inventoryProducts => throw _privateConstructorUsedError;
  bool get isLoadingProducts => throw _privateConstructorUsedError;
  String? get errorMessage =>
      throw _privateConstructorUsedError; // Background task status
  String? get backgroundTaskMessage => throw _privateConstructorUsedError;
  bool get isBackgroundTaskRunning =>
      throw _privateConstructorUsedError; // Product selection for batch operations
  Set<String> get selectedProductIds =>
      throw _privateConstructorUsedError; // Categorized view
  List<ProductCategoryGroup> get categorizedProductGroups =>
      throw _privateConstructorUsedError;
  List<Map<String, dynamic>> get allCategories =>
      throw _privateConstructorUsedError;
  Set<int> get expandedCategoryIds => throw _privateConstructorUsedError;
  Set<String> get expandedVariableProductIds =>
      throw _privateConstructorUsedError;

  /// Create a copy of InventoryState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $InventoryStateCopyWith<InventoryState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $InventoryStateCopyWith<$Res> {
  factory $InventoryStateCopyWith(
          InventoryState value, $Res Function(InventoryState) then) =
      _$InventoryStateCopyWithImpl<$Res, InventoryState>;
  @useResult
  $Res call(
      {List<InventoryMovement> inventoryMovements,
      int movementsCurrentPage,
      bool movementsIsLoading,
      bool movementsIsLoadingMore,
      bool movementsCanLoadMore,
      String? movementsError,
      int movementsTotalPages,
      List<Product> inventoryProducts,
      bool isLoadingProducts,
      String? errorMessage,
      String? backgroundTaskMessage,
      bool isBackgroundTaskRunning,
      Set<String> selectedProductIds,
      List<ProductCategoryGroup> categorizedProductGroups,
      List<Map<String, dynamic>> allCategories,
      Set<int> expandedCategoryIds,
      Set<String> expandedVariableProductIds});
}

/// @nodoc
class _$InventoryStateCopyWithImpl<$Res, $Val extends InventoryState>
    implements $InventoryStateCopyWith<$Res> {
  _$InventoryStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of InventoryState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? inventoryMovements = null,
    Object? movementsCurrentPage = null,
    Object? movementsIsLoading = null,
    Object? movementsIsLoadingMore = null,
    Object? movementsCanLoadMore = null,
    Object? movementsError = freezed,
    Object? movementsTotalPages = null,
    Object? inventoryProducts = null,
    Object? isLoadingProducts = null,
    Object? errorMessage = freezed,
    Object? backgroundTaskMessage = freezed,
    Object? isBackgroundTaskRunning = null,
    Object? selectedProductIds = null,
    Object? categorizedProductGroups = null,
    Object? allCategories = null,
    Object? expandedCategoryIds = null,
    Object? expandedVariableProductIds = null,
  }) {
    return _then(_value.copyWith(
      inventoryMovements: null == inventoryMovements
          ? _value.inventoryMovements
          : inventoryMovements // ignore: cast_nullable_to_non_nullable
              as List<InventoryMovement>,
      movementsCurrentPage: null == movementsCurrentPage
          ? _value.movementsCurrentPage
          : movementsCurrentPage // ignore: cast_nullable_to_non_nullable
              as int,
      movementsIsLoading: null == movementsIsLoading
          ? _value.movementsIsLoading
          : movementsIsLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      movementsIsLoadingMore: null == movementsIsLoadingMore
          ? _value.movementsIsLoadingMore
          : movementsIsLoadingMore // ignore: cast_nullable_to_non_nullable
              as bool,
      movementsCanLoadMore: null == movementsCanLoadMore
          ? _value.movementsCanLoadMore
          : movementsCanLoadMore // ignore: cast_nullable_to_non_nullable
              as bool,
      movementsError: freezed == movementsError
          ? _value.movementsError
          : movementsError // ignore: cast_nullable_to_non_nullable
              as String?,
      movementsTotalPages: null == movementsTotalPages
          ? _value.movementsTotalPages
          : movementsTotalPages // ignore: cast_nullable_to_non_nullable
              as int,
      inventoryProducts: null == inventoryProducts
          ? _value.inventoryProducts
          : inventoryProducts // ignore: cast_nullable_to_non_nullable
              as List<Product>,
      isLoadingProducts: null == isLoadingProducts
          ? _value.isLoadingProducts
          : isLoadingProducts // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      backgroundTaskMessage: freezed == backgroundTaskMessage
          ? _value.backgroundTaskMessage
          : backgroundTaskMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      isBackgroundTaskRunning: null == isBackgroundTaskRunning
          ? _value.isBackgroundTaskRunning
          : isBackgroundTaskRunning // ignore: cast_nullable_to_non_nullable
              as bool,
      selectedProductIds: null == selectedProductIds
          ? _value.selectedProductIds
          : selectedProductIds // ignore: cast_nullable_to_non_nullable
              as Set<String>,
      categorizedProductGroups: null == categorizedProductGroups
          ? _value.categorizedProductGroups
          : categorizedProductGroups // ignore: cast_nullable_to_non_nullable
              as List<ProductCategoryGroup>,
      allCategories: null == allCategories
          ? _value.allCategories
          : allCategories // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      expandedCategoryIds: null == expandedCategoryIds
          ? _value.expandedCategoryIds
          : expandedCategoryIds // ignore: cast_nullable_to_non_nullable
              as Set<int>,
      expandedVariableProductIds: null == expandedVariableProductIds
          ? _value.expandedVariableProductIds
          : expandedVariableProductIds // ignore: cast_nullable_to_non_nullable
              as Set<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$InventoryStateImplCopyWith<$Res>
    implements $InventoryStateCopyWith<$Res> {
  factory _$$InventoryStateImplCopyWith(_$InventoryStateImpl value,
          $Res Function(_$InventoryStateImpl) then) =
      __$$InventoryStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<InventoryMovement> inventoryMovements,
      int movementsCurrentPage,
      bool movementsIsLoading,
      bool movementsIsLoadingMore,
      bool movementsCanLoadMore,
      String? movementsError,
      int movementsTotalPages,
      List<Product> inventoryProducts,
      bool isLoadingProducts,
      String? errorMessage,
      String? backgroundTaskMessage,
      bool isBackgroundTaskRunning,
      Set<String> selectedProductIds,
      List<ProductCategoryGroup> categorizedProductGroups,
      List<Map<String, dynamic>> allCategories,
      Set<int> expandedCategoryIds,
      Set<String> expandedVariableProductIds});
}

/// @nodoc
class __$$InventoryStateImplCopyWithImpl<$Res>
    extends _$InventoryStateCopyWithImpl<$Res, _$InventoryStateImpl>
    implements _$$InventoryStateImplCopyWith<$Res> {
  __$$InventoryStateImplCopyWithImpl(
      _$InventoryStateImpl _value, $Res Function(_$InventoryStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of InventoryState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? inventoryMovements = null,
    Object? movementsCurrentPage = null,
    Object? movementsIsLoading = null,
    Object? movementsIsLoadingMore = null,
    Object? movementsCanLoadMore = null,
    Object? movementsError = freezed,
    Object? movementsTotalPages = null,
    Object? inventoryProducts = null,
    Object? isLoadingProducts = null,
    Object? errorMessage = freezed,
    Object? backgroundTaskMessage = freezed,
    Object? isBackgroundTaskRunning = null,
    Object? selectedProductIds = null,
    Object? categorizedProductGroups = null,
    Object? allCategories = null,
    Object? expandedCategoryIds = null,
    Object? expandedVariableProductIds = null,
  }) {
    return _then(_$InventoryStateImpl(
      inventoryMovements: null == inventoryMovements
          ? _value._inventoryMovements
          : inventoryMovements // ignore: cast_nullable_to_non_nullable
              as List<InventoryMovement>,
      movementsCurrentPage: null == movementsCurrentPage
          ? _value.movementsCurrentPage
          : movementsCurrentPage // ignore: cast_nullable_to_non_nullable
              as int,
      movementsIsLoading: null == movementsIsLoading
          ? _value.movementsIsLoading
          : movementsIsLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      movementsIsLoadingMore: null == movementsIsLoadingMore
          ? _value.movementsIsLoadingMore
          : movementsIsLoadingMore // ignore: cast_nullable_to_non_nullable
              as bool,
      movementsCanLoadMore: null == movementsCanLoadMore
          ? _value.movementsCanLoadMore
          : movementsCanLoadMore // ignore: cast_nullable_to_non_nullable
              as bool,
      movementsError: freezed == movementsError
          ? _value.movementsError
          : movementsError // ignore: cast_nullable_to_non_nullable
              as String?,
      movementsTotalPages: null == movementsTotalPages
          ? _value.movementsTotalPages
          : movementsTotalPages // ignore: cast_nullable_to_non_nullable
              as int,
      inventoryProducts: null == inventoryProducts
          ? _value._inventoryProducts
          : inventoryProducts // ignore: cast_nullable_to_non_nullable
              as List<Product>,
      isLoadingProducts: null == isLoadingProducts
          ? _value.isLoadingProducts
          : isLoadingProducts // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      backgroundTaskMessage: freezed == backgroundTaskMessage
          ? _value.backgroundTaskMessage
          : backgroundTaskMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      isBackgroundTaskRunning: null == isBackgroundTaskRunning
          ? _value.isBackgroundTaskRunning
          : isBackgroundTaskRunning // ignore: cast_nullable_to_non_nullable
              as bool,
      selectedProductIds: null == selectedProductIds
          ? _value._selectedProductIds
          : selectedProductIds // ignore: cast_nullable_to_non_nullable
              as Set<String>,
      categorizedProductGroups: null == categorizedProductGroups
          ? _value._categorizedProductGroups
          : categorizedProductGroups // ignore: cast_nullable_to_non_nullable
              as List<ProductCategoryGroup>,
      allCategories: null == allCategories
          ? _value._allCategories
          : allCategories // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      expandedCategoryIds: null == expandedCategoryIds
          ? _value._expandedCategoryIds
          : expandedCategoryIds // ignore: cast_nullable_to_non_nullable
              as Set<int>,
      expandedVariableProductIds: null == expandedVariableProductIds
          ? _value._expandedVariableProductIds
          : expandedVariableProductIds // ignore: cast_nullable_to_non_nullable
              as Set<String>,
    ));
  }
}

/// @nodoc

class _$InventoryStateImpl extends _InventoryState
    with DiagnosticableTreeMixin {
  const _$InventoryStateImpl(
      {final List<InventoryMovement> inventoryMovements = const [],
      this.movementsCurrentPage = 1,
      this.movementsIsLoading = false,
      this.movementsIsLoadingMore = false,
      this.movementsCanLoadMore = true,
      this.movementsError,
      this.movementsTotalPages = 1,
      final List<Product> inventoryProducts = const [],
      this.isLoadingProducts = false,
      this.errorMessage,
      this.backgroundTaskMessage,
      this.isBackgroundTaskRunning = false,
      final Set<String> selectedProductIds = const {},
      final List<ProductCategoryGroup> categorizedProductGroups = const [],
      final List<Map<String, dynamic>> allCategories = const [],
      final Set<int> expandedCategoryIds = const {},
      final Set<String> expandedVariableProductIds = const {}})
      : _inventoryMovements = inventoryMovements,
        _inventoryProducts = inventoryProducts,
        _selectedProductIds = selectedProductIds,
        _categorizedProductGroups = categorizedProductGroups,
        _allCategories = allCategories,
        _expandedCategoryIds = expandedCategoryIds,
        _expandedVariableProductIds = expandedVariableProductIds,
        super._();

// Inventory movements (history) with pagination
  final List<InventoryMovement> _inventoryMovements;
// Inventory movements (history) with pagination
  @override
  @JsonKey()
  List<InventoryMovement> get inventoryMovements {
    if (_inventoryMovements is EqualUnmodifiableListView)
      return _inventoryMovements;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_inventoryMovements);
  }

  @override
  @JsonKey()
  final int movementsCurrentPage;
  @override
  @JsonKey()
  final bool movementsIsLoading;
  @override
  @JsonKey()
  final bool movementsIsLoadingMore;
  @override
  @JsonKey()
  final bool movementsCanLoadMore;
  @override
  final String? movementsError;
  @override
  @JsonKey()
  final int movementsTotalPages;
// Inventory products management
  final List<Product> _inventoryProducts;
// Inventory products management
  @override
  @JsonKey()
  List<Product> get inventoryProducts {
    if (_inventoryProducts is EqualUnmodifiableListView)
      return _inventoryProducts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_inventoryProducts);
  }

  @override
  @JsonKey()
  final bool isLoadingProducts;
  @override
  final String? errorMessage;
// Background task status
  @override
  final String? backgroundTaskMessage;
  @override
  @JsonKey()
  final bool isBackgroundTaskRunning;
// Product selection for batch operations
  final Set<String> _selectedProductIds;
// Product selection for batch operations
  @override
  @JsonKey()
  Set<String> get selectedProductIds {
    if (_selectedProductIds is EqualUnmodifiableSetView)
      return _selectedProductIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_selectedProductIds);
  }

// Categorized view
  final List<ProductCategoryGroup> _categorizedProductGroups;
// Categorized view
  @override
  @JsonKey()
  List<ProductCategoryGroup> get categorizedProductGroups {
    if (_categorizedProductGroups is EqualUnmodifiableListView)
      return _categorizedProductGroups;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_categorizedProductGroups);
  }

  final List<Map<String, dynamic>> _allCategories;
  @override
  @JsonKey()
  List<Map<String, dynamic>> get allCategories {
    if (_allCategories is EqualUnmodifiableListView) return _allCategories;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_allCategories);
  }

  final Set<int> _expandedCategoryIds;
  @override
  @JsonKey()
  Set<int> get expandedCategoryIds {
    if (_expandedCategoryIds is EqualUnmodifiableSetView)
      return _expandedCategoryIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_expandedCategoryIds);
  }

  final Set<String> _expandedVariableProductIds;
  @override
  @JsonKey()
  Set<String> get expandedVariableProductIds {
    if (_expandedVariableProductIds is EqualUnmodifiableSetView)
      return _expandedVariableProductIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_expandedVariableProductIds);
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'InventoryState(inventoryMovements: $inventoryMovements, movementsCurrentPage: $movementsCurrentPage, movementsIsLoading: $movementsIsLoading, movementsIsLoadingMore: $movementsIsLoadingMore, movementsCanLoadMore: $movementsCanLoadMore, movementsError: $movementsError, movementsTotalPages: $movementsTotalPages, inventoryProducts: $inventoryProducts, isLoadingProducts: $isLoadingProducts, errorMessage: $errorMessage, backgroundTaskMessage: $backgroundTaskMessage, isBackgroundTaskRunning: $isBackgroundTaskRunning, selectedProductIds: $selectedProductIds, categorizedProductGroups: $categorizedProductGroups, allCategories: $allCategories, expandedCategoryIds: $expandedCategoryIds, expandedVariableProductIds: $expandedVariableProductIds)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'InventoryState'))
      ..add(DiagnosticsProperty('inventoryMovements', inventoryMovements))
      ..add(DiagnosticsProperty('movementsCurrentPage', movementsCurrentPage))
      ..add(DiagnosticsProperty('movementsIsLoading', movementsIsLoading))
      ..add(
          DiagnosticsProperty('movementsIsLoadingMore', movementsIsLoadingMore))
      ..add(DiagnosticsProperty('movementsCanLoadMore', movementsCanLoadMore))
      ..add(DiagnosticsProperty('movementsError', movementsError))
      ..add(DiagnosticsProperty('movementsTotalPages', movementsTotalPages))
      ..add(DiagnosticsProperty('inventoryProducts', inventoryProducts))
      ..add(DiagnosticsProperty('isLoadingProducts', isLoadingProducts))
      ..add(DiagnosticsProperty('errorMessage', errorMessage))
      ..add(DiagnosticsProperty('backgroundTaskMessage', backgroundTaskMessage))
      ..add(DiagnosticsProperty(
          'isBackgroundTaskRunning', isBackgroundTaskRunning))
      ..add(DiagnosticsProperty('selectedProductIds', selectedProductIds))
      ..add(DiagnosticsProperty(
          'categorizedProductGroups', categorizedProductGroups))
      ..add(DiagnosticsProperty('allCategories', allCategories))
      ..add(DiagnosticsProperty('expandedCategoryIds', expandedCategoryIds))
      ..add(DiagnosticsProperty(
          'expandedVariableProductIds', expandedVariableProductIds));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InventoryStateImpl &&
            const DeepCollectionEquality()
                .equals(other._inventoryMovements, _inventoryMovements) &&
            (identical(other.movementsCurrentPage, movementsCurrentPage) ||
                other.movementsCurrentPage == movementsCurrentPage) &&
            (identical(other.movementsIsLoading, movementsIsLoading) ||
                other.movementsIsLoading == movementsIsLoading) &&
            (identical(other.movementsIsLoadingMore, movementsIsLoadingMore) ||
                other.movementsIsLoadingMore == movementsIsLoadingMore) &&
            (identical(other.movementsCanLoadMore, movementsCanLoadMore) ||
                other.movementsCanLoadMore == movementsCanLoadMore) &&
            (identical(other.movementsError, movementsError) ||
                other.movementsError == movementsError) &&
            (identical(other.movementsTotalPages, movementsTotalPages) ||
                other.movementsTotalPages == movementsTotalPages) &&
            const DeepCollectionEquality()
                .equals(other._inventoryProducts, _inventoryProducts) &&
            (identical(other.isLoadingProducts, isLoadingProducts) ||
                other.isLoadingProducts == isLoadingProducts) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.backgroundTaskMessage, backgroundTaskMessage) ||
                other.backgroundTaskMessage == backgroundTaskMessage) &&
            (identical(
                    other.isBackgroundTaskRunning, isBackgroundTaskRunning) ||
                other.isBackgroundTaskRunning == isBackgroundTaskRunning) &&
            const DeepCollectionEquality()
                .equals(other._selectedProductIds, _selectedProductIds) &&
            const DeepCollectionEquality().equals(
                other._categorizedProductGroups, _categorizedProductGroups) &&
            const DeepCollectionEquality()
                .equals(other._allCategories, _allCategories) &&
            const DeepCollectionEquality()
                .equals(other._expandedCategoryIds, _expandedCategoryIds) &&
            const DeepCollectionEquality().equals(
                other._expandedVariableProductIds,
                _expandedVariableProductIds));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_inventoryMovements),
      movementsCurrentPage,
      movementsIsLoading,
      movementsIsLoadingMore,
      movementsCanLoadMore,
      movementsError,
      movementsTotalPages,
      const DeepCollectionEquality().hash(_inventoryProducts),
      isLoadingProducts,
      errorMessage,
      backgroundTaskMessage,
      isBackgroundTaskRunning,
      const DeepCollectionEquality().hash(_selectedProductIds),
      const DeepCollectionEquality().hash(_categorizedProductGroups),
      const DeepCollectionEquality().hash(_allCategories),
      const DeepCollectionEquality().hash(_expandedCategoryIds),
      const DeepCollectionEquality().hash(_expandedVariableProductIds));

  /// Create a copy of InventoryState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$InventoryStateImplCopyWith<_$InventoryStateImpl> get copyWith =>
      __$$InventoryStateImplCopyWithImpl<_$InventoryStateImpl>(
          this, _$identity);
}

abstract class _InventoryState extends InventoryState {
  const factory _InventoryState(
      {final List<InventoryMovement> inventoryMovements,
      final int movementsCurrentPage,
      final bool movementsIsLoading,
      final bool movementsIsLoadingMore,
      final bool movementsCanLoadMore,
      final String? movementsError,
      final int movementsTotalPages,
      final List<Product> inventoryProducts,
      final bool isLoadingProducts,
      final String? errorMessage,
      final String? backgroundTaskMessage,
      final bool isBackgroundTaskRunning,
      final Set<String> selectedProductIds,
      final List<ProductCategoryGroup> categorizedProductGroups,
      final List<Map<String, dynamic>> allCategories,
      final Set<int> expandedCategoryIds,
      final Set<String> expandedVariableProductIds}) = _$InventoryStateImpl;
  const _InventoryState._() : super._();

// Inventory movements (history) with pagination
  @override
  List<InventoryMovement> get inventoryMovements;
  @override
  int get movementsCurrentPage;
  @override
  bool get movementsIsLoading;
  @override
  bool get movementsIsLoadingMore;
  @override
  bool get movementsCanLoadMore;
  @override
  String? get movementsError;
  @override
  int get movementsTotalPages; // Inventory products management
  @override
  List<Product> get inventoryProducts;
  @override
  bool get isLoadingProducts;
  @override
  String? get errorMessage; // Background task status
  @override
  String? get backgroundTaskMessage;
  @override
  bool get isBackgroundTaskRunning; // Product selection for batch operations
  @override
  Set<String> get selectedProductIds; // Categorized view
  @override
  List<ProductCategoryGroup> get categorizedProductGroups;
  @override
  List<Map<String, dynamic>> get allCategories;
  @override
  Set<int> get expandedCategoryIds;
  @override
  Set<String> get expandedVariableProductIds;

  /// Create a copy of InventoryState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$InventoryStateImplCopyWith<_$InventoryStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
