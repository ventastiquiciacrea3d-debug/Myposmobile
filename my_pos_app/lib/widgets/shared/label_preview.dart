// lib/widgets/shared/label_preview.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/label_print_item.dart';

class LabelPreview extends StatelessWidget {
  final LabelSettings settings;
  final SerializableLabelData data;

  const LabelPreview({
    Key? key,
    required this.settings,
    required this.data,
  }) : super(key: key);

  static Map<String, dynamic> _getFontStyles(String sizeKey, String weightKey) {
    const Map<String, double> sizeMap = {'small': 10.0, 'medium': 12.0, 'large': 15.0};
    const Map<String, FontWeight> weightMap = {'light': FontWeight.w300, 'normal': FontWeight.normal, 'bold': FontWeight.bold};
    return {'size': sizeMap[sizeKey] ?? 12.0, 'weight': weightMap[weightKey] ?? FontWeight.normal};
  }

  String _getTextForKey(String key) {
    switch (key) {
      case 'productName': return data.displayName;
      case 'variants': return data.selectedVariants.values.join(' / ');
      case 'quantity': return 'Cant: ${data.quantity}';
      case 'lotNumber': return 'Lote: ${data.lotNumber ?? ""}';
      case 'date': return data.date;
      case 'brand': return data.brand;
      case 'sku': return 'SKU: ${data.displaySku}';
      default: return key;
    }
  }

  TextAlign _getTextAlign(String alignKey) {
    switch (alignKey) {
      case 'center': return TextAlign.center;
      case 'right': return TextAlign.right;
      case 'left': default: return TextAlign.left;
    }
  }

  @override
  Widget build(BuildContext context) {
    const double previewContainerWidth = 250;
    final double labelWidthMm = settings.labelLayout['width'] ?? 50.0;
    final double labelHeightMm = settings.labelLayout['height'] ?? 38.0;
    final double previewContainerHeight = (previewContainerWidth * labelHeightMm) / labelWidthMm;
    final int widthDots = (labelWidthMm * 8).round();
    final double scaleFactor = previewContainerWidth / widthDots;
    const int topMargin = 15;
    const int bottomMargin = 15;
    const int horizontalMargin = 15;
    final int printableWidthDots = widthDots - (2 * horizontalMargin);
    List<Widget> positionedWidgets = [];
    int currentYDots = topMargin;
    int textBottomBoundaryDots = (labelHeightMm * 8).round() - bottomMargin;

    final bool isBarcodeVisible = settings.visibleAttributes['barcode'] ?? true;
    final String barcodeData = data.barcode ?? data.displaySku;

    if (isBarcodeVisible && barcodeData.isNotEmpty) {
      final int barcodeHeightDots = ((labelHeightMm * 8).round() * 0.25).round().clamp(40, 70);
      const int barcodeTextHeightDots = 25;
      const int barcodeAreaGapDots = 8;
      final int barcodeTotalHeightDots = barcodeHeightDots + barcodeTextHeightDots + barcodeAreaGapDots;
      final int barcodeAreaTopYDots = (labelHeightMm * 8).round() - bottomMargin - barcodeTotalHeightDots;
      textBottomBoundaryDots = barcodeAreaTopYDots;

      positionedWidgets.add(
        Positioned(
          top: (barcodeAreaTopYDots + barcodeAreaGapDots) * scaleFactor,
          left: horizontalMargin * scaleFactor,
          right: horizontalMargin * scaleFactor,
          height: (barcodeHeightDots + barcodeTextHeightDots) * scaleFactor,
          child: _BarcodePlaceholder(
            text: data.displaySku,
            height: barcodeHeightDots * scaleFactor,
          ),
        ),
      );
    }

    final visible = settings.visibleAttributes;
    final layouts = settings.fieldLayouts;
    final fieldsToDraw = settings.fieldOrder.where((k) => (visible[k] ?? false) && k != 'barcode').toList();

    final rows = <List<String>>[];
    for (var i = 0; i < fieldsToDraw.length;) {
      final key1 = fieldsToDraw[i];
      final columns = layouts[key1]?['columns'] ?? 1;
      if (columns == 1 || i + 1 >= fieldsToDraw.length) {
        rows.add([key1]);
        i++;
      } else {
        rows.add([key1, fieldsToDraw[i + 1]]);
        i += 2;
      }
    }

    for (final row in rows) {
      final rowItemsData = row.map((key) {
        final text = _getTextForKey(key);
        if (text.isEmpty) return null;
        return {'key': key, 'text': text, 'layout': layouts[key] ?? {}};
      }).where((item) => item != null).cast<Map<String,dynamic>>().toList();

      if (rowItemsData.isEmpty) continue;

      double maxFontSize = 12.0;
      double maxSpacingMultiplier = 1.0;

      if (rowItemsData.isNotEmpty) {
        final layout1 = rowItemsData[0]['layout'];
        maxSpacingMultiplier = (layout1['spacing'] as num?)?.toDouble() ?? 1.5;
        final styles1 = _getFontStyles(layout1['size'] ?? 'medium', layout1['weight'] ?? 'normal');
        maxFontSize = styles1['size'];

        if (rowItemsData.length > 1) {
          final layout2 = rowItemsData[1]['layout'];
          final spacing2 = (layout2['spacing'] as num?)?.toDouble() ?? 1.5;
          maxSpacingMultiplier = max(maxSpacingMultiplier, spacing2);
          final styles2 = _getFontStyles(layout2['size'] ?? 'medium', layout2['weight'] ?? 'normal');
          maxFontSize = max(maxFontSize, styles2['size']);
        }
      }
      final double maxRowHeightPx = maxFontSize * 1.4;
      final int maxRowHeightDots = (maxRowHeightPx / scaleFactor).round();

      if (currentYDots + maxRowHeightDots < textBottomBoundaryDots) {
        positionedWidgets.add(
          Positioned(
            top: currentYDots * scaleFactor,
            left: horizontalMargin * scaleFactor,
            width: printableWidthDots * scaleFactor,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: rowItemsData.map((itemData) {
                final layout = itemData['layout'];
                return Expanded(
                  child: _FieldText(
                    text: itemData['text'],
                    textAlign: _getTextAlign(layout['align'] ?? 'left'),
                    sizeKey: layout['size'] ?? 'medium',
                    weightKey: layout['weight'] ?? 'normal',
                    fitKey: layout['fit'] ?? 'truncate',
                  ),
                );
              }).toList(),
            ),
          ),
        );
        currentYDots += (maxRowHeightDots * maxSpacingMultiplier).round();
      } else {
        break;
      }
    }

    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: previewContainerWidth,
        height: previewContainerHeight,
        color: Colors.white,
        child: Stack(children: positionedWidgets),
      ),
    );
  }
}

class _FieldText extends StatelessWidget {
  final String text;
  final String sizeKey;
  final String weightKey;
  final String fitKey;
  final TextAlign textAlign;

  const _FieldText({
    required this.text,
    this.sizeKey = 'medium',
    this.weightKey = 'normal',
    this.fitKey = 'truncate',
    this.textAlign = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final styles = LabelPreview._getFontStyles(sizeKey, weightKey);
    final style = TextStyle(
      fontSize: styles['size'],
      fontWeight: styles['weight'],
      color: const Color(0xFF1F2937),
      height: 1.1,
    );

    if (fitKey == 'wrap') {
      return Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: textAlign);
    }
    return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: textAlign);
  }
}

class _BarcodePlaceholder extends StatelessWidget {
  final String text;
  final double height;
  const _BarcodePlaceholder({required this.text, required this.height});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(35, (index) {
              final random = Random(index);
              return Expanded(
                flex: random.nextInt(4) + 1,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  color: index % 2 == 0 ? Colors.black : Colors.white,
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 9, letterSpacing: 1.2),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}