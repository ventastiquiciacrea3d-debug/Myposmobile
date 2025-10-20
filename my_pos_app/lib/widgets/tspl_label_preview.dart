// lib/widgets/tspl_label_preview.dart
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import '../models/label_print_item.dart';
import 'shared/label_preview.dart';

class TsplLabelPreview extends StatelessWidget {
  final LabelPrintItem item;
  final LabelSettings settings;

  const TsplLabelPreview({
    Key? key,
    required this.item,
    required this.settings,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serializableData = SerializableLabelData(
      displayName: item.displayName,
      displaySku: item.displaySku,
      quantity: item.quantity,
      selectedVariants: item.selectedVariants,
      brand: (item.product?.attributes?.firstWhereOrNull(
              (attr) => attr['name']?.toLowerCase() == 'brand' || attr['name']?.toLowerCase() == 'marca'
      )?['option'] as String?) ?? '',
      barcode: item.barcode ?? item.displaySku,
      lotNumber: item.lotNumber,
      date: DateFormat('dd/MM/yy', 'es_CR').format(DateTime.now()),
    );

    return LabelPreview(
      settings: settings,
      data: serializableData,
    );
  }
}