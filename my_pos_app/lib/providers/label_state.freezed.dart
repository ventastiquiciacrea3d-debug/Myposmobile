// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'label_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$LabelState {
  List<LabelPrintItem> get printQueue => throw _privateConstructorUsedError;
  LabelSettings get settings => throw _privateConstructorUsedError;
  bool get isPrinting => throw _privateConstructorUsedError;
  bool get isQueueLoaded => throw _privateConstructorUsedError;
  LabelPrintItem? get itemBeingEdited => throw _privateConstructorUsedError;

  /// Create a copy of LabelState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $LabelStateCopyWith<LabelState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LabelStateCopyWith<$Res> {
  factory $LabelStateCopyWith(
          LabelState value, $Res Function(LabelState) then) =
      _$LabelStateCopyWithImpl<$Res, LabelState>;
  @useResult
  $Res call(
      {List<LabelPrintItem> printQueue,
      LabelSettings settings,
      bool isPrinting,
      bool isQueueLoaded,
      LabelPrintItem? itemBeingEdited});
}

/// @nodoc
class _$LabelStateCopyWithImpl<$Res, $Val extends LabelState>
    implements $LabelStateCopyWith<$Res> {
  _$LabelStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of LabelState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? printQueue = null,
    Object? settings = null,
    Object? isPrinting = null,
    Object? isQueueLoaded = null,
    Object? itemBeingEdited = freezed,
  }) {
    return _then(_value.copyWith(
      printQueue: null == printQueue
          ? _value.printQueue
          : printQueue // ignore: cast_nullable_to_non_nullable
              as List<LabelPrintItem>,
      settings: null == settings
          ? _value.settings
          : settings // ignore: cast_nullable_to_non_nullable
              as LabelSettings,
      isPrinting: null == isPrinting
          ? _value.isPrinting
          : isPrinting // ignore: cast_nullable_to_non_nullable
              as bool,
      isQueueLoaded: null == isQueueLoaded
          ? _value.isQueueLoaded
          : isQueueLoaded // ignore: cast_nullable_to_non_nullable
              as bool,
      itemBeingEdited: freezed == itemBeingEdited
          ? _value.itemBeingEdited
          : itemBeingEdited // ignore: cast_nullable_to_non_nullable
              as LabelPrintItem?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$LabelStateImplCopyWith<$Res>
    implements $LabelStateCopyWith<$Res> {
  factory _$$LabelStateImplCopyWith(
          _$LabelStateImpl value, $Res Function(_$LabelStateImpl) then) =
      __$$LabelStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<LabelPrintItem> printQueue,
      LabelSettings settings,
      bool isPrinting,
      bool isQueueLoaded,
      LabelPrintItem? itemBeingEdited});
}

/// @nodoc
class __$$LabelStateImplCopyWithImpl<$Res>
    extends _$LabelStateCopyWithImpl<$Res, _$LabelStateImpl>
    implements _$$LabelStateImplCopyWith<$Res> {
  __$$LabelStateImplCopyWithImpl(
      _$LabelStateImpl _value, $Res Function(_$LabelStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of LabelState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? printQueue = null,
    Object? settings = null,
    Object? isPrinting = null,
    Object? isQueueLoaded = null,
    Object? itemBeingEdited = freezed,
  }) {
    return _then(_$LabelStateImpl(
      printQueue: null == printQueue
          ? _value._printQueue
          : printQueue // ignore: cast_nullable_to_non_nullable
              as List<LabelPrintItem>,
      settings: null == settings
          ? _value.settings
          : settings // ignore: cast_nullable_to_non_nullable
              as LabelSettings,
      isPrinting: null == isPrinting
          ? _value.isPrinting
          : isPrinting // ignore: cast_nullable_to_non_nullable
              as bool,
      isQueueLoaded: null == isQueueLoaded
          ? _value.isQueueLoaded
          : isQueueLoaded // ignore: cast_nullable_to_non_nullable
              as bool,
      itemBeingEdited: freezed == itemBeingEdited
          ? _value.itemBeingEdited
          : itemBeingEdited // ignore: cast_nullable_to_non_nullable
              as LabelPrintItem?,
    ));
  }
}

/// @nodoc

class _$LabelStateImpl extends _LabelState with DiagnosticableTreeMixin {
  const _$LabelStateImpl(
      {final List<LabelPrintItem> printQueue = const [],
      this.settings = const LabelSettings(),
      this.isPrinting = false,
      this.isQueueLoaded = false,
      this.itemBeingEdited})
      : _printQueue = printQueue,
        super._();

  final List<LabelPrintItem> _printQueue;
  @override
  @JsonKey()
  List<LabelPrintItem> get printQueue {
    if (_printQueue is EqualUnmodifiableListView) return _printQueue;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_printQueue);
  }

  @override
  @JsonKey()
  final LabelSettings settings;
  @override
  @JsonKey()
  final bool isPrinting;
  @override
  @JsonKey()
  final bool isQueueLoaded;
  @override
  final LabelPrintItem? itemBeingEdited;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'LabelState(printQueue: $printQueue, settings: $settings, isPrinting: $isPrinting, isQueueLoaded: $isQueueLoaded, itemBeingEdited: $itemBeingEdited)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'LabelState'))
      ..add(DiagnosticsProperty('printQueue', printQueue))
      ..add(DiagnosticsProperty('settings', settings))
      ..add(DiagnosticsProperty('isPrinting', isPrinting))
      ..add(DiagnosticsProperty('isQueueLoaded', isQueueLoaded))
      ..add(DiagnosticsProperty('itemBeingEdited', itemBeingEdited));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LabelStateImpl &&
            const DeepCollectionEquality()
                .equals(other._printQueue, _printQueue) &&
            (identical(other.settings, settings) ||
                other.settings == settings) &&
            (identical(other.isPrinting, isPrinting) ||
                other.isPrinting == isPrinting) &&
            (identical(other.isQueueLoaded, isQueueLoaded) ||
                other.isQueueLoaded == isQueueLoaded) &&
            (identical(other.itemBeingEdited, itemBeingEdited) ||
                other.itemBeingEdited == itemBeingEdited));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_printQueue),
      settings,
      isPrinting,
      isQueueLoaded,
      itemBeingEdited);

  /// Create a copy of LabelState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$LabelStateImplCopyWith<_$LabelStateImpl> get copyWith =>
      __$$LabelStateImplCopyWithImpl<_$LabelStateImpl>(this, _$identity);
}

abstract class _LabelState extends LabelState {
  const factory _LabelState(
      {final List<LabelPrintItem> printQueue,
      final LabelSettings settings,
      final bool isPrinting,
      final bool isQueueLoaded,
      final LabelPrintItem? itemBeingEdited}) = _$LabelStateImpl;
  const _LabelState._() : super._();

  @override
  List<LabelPrintItem> get printQueue;
  @override
  LabelSettings get settings;
  @override
  bool get isPrinting;
  @override
  bool get isQueueLoaded;
  @override
  LabelPrintItem? get itemBeingEdited;

  /// Create a copy of LabelState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$LabelStateImplCopyWith<_$LabelStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
