// lib/providers/label_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

import '../models/label_print_item.dart';

part 'label_state.freezed.dart';

/// ✓ FASE 2 RIVERPOD: Estado inmutable para Label printing
@freezed
class LabelState with _$LabelState {
  const factory LabelState({
    @Default([]) List<LabelPrintItem> printQueue,
    @Default(LabelSettings()) LabelSettings settings,
    @Default(false) bool isPrinting,
    @Default(false) bool isQueueLoaded,
    LabelPrintItem? itemBeingEdited,
  }) = _LabelState;

  const LabelState._();

  factory LabelState.initial() => const LabelState();

  String? get editingItemId => itemBeingEdited?.id;
}
