// lib/services/label_converter_service.dart
import '../models/label_print_item.dart';
import '../models/label_print_item_compact.dart';

/// Servicio para convertir entre LabelPrintItem (legacy Hive) y LabelPrintItemCompact (ObjectBox)
class LabelConverterService {
  /// Convertir LabelPrintItem (Hive) a LabelPrintItemCompact (ObjectBox)
  LabelPrintItemCompact labelToCompact(LabelPrintItem label) {
    // Parse product ID
    final int productId = int.tryParse(label.productId) ?? 0;

    // Parse variation ID
    final int variationId = label.resolvedVariantId != null ? (int.tryParse(label.resolvedVariantId!) ?? 0) : 0;

    // Extract brand from product attributes
    final brandAttribute = label.product?.attributes?.firstWhere(
      (attr) => attr['name']?.toString().toLowerCase() == 'brand' ||
                attr['name']?.toString().toLowerCase() == 'marca',
      orElse: () => {},
    );
    final brandName = brandAttribute?['option']?.toString() ?? '';

    // Build variant text from selectedVariants
    final variantText = label.selectedVariants.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');

    return LabelPrintItemCompact(
      itemId: label.id ?? '',
      productId: productId,
      variationId: variationId,
      productName: _truncate(label.displayName, 50),
      sku: _truncate(label.displaySku, 20),
      barcode: label.barcode != null ? _truncate(label.barcode!, 13) : null,
      brand: brandName.isNotEmpty ? _truncate(brandName, 30) : null,
      variantText: variantText.isNotEmpty ? _truncate(variantText, 50) : null,
      lotNumber: label.lotNumber != null ? _truncate(label.lotNumber!, 20) : null,
      quantity: label.quantity,
      labelDate: null, // Not stored in original model
      createdAt: DateTime.now(), // Not stored in original model
      flags: 0, // isPrinted not available in original model
    );
  }

  /// Convertir LabelPrintItemCompact (ObjectBox) a LabelPrintItem (Hive)
  ///
  /// ⚡ OPTIMIZACIÓN: Este método ya no carga los productos completos.
  /// Los productos se cargarán bajo demanda cuando se necesiten.
  LabelPrintItem compactToLabel(LabelPrintItemCompact compact) {
    // Parse selectedVariants from variantText
    final Map<String, String> selectedVariants = {};
    if (compact.variantText != null && compact.variantText!.isNotEmpty) {
      final pairs = compact.variantText!.split(', ');
      for (final pair in pairs) {
        final parts = pair.split(': ');
        if (parts.length == 2) {
          selectedVariants[parts[0]] = parts[1];
        }
      }
    }

    return LabelPrintItem(
      id: compact.itemId,
      productId: compact.productId.toString(),
      resolvedVariantId: compact.variationId > 0 ? compact.variationId.toString() : null,
      quantity: compact.quantity,
      selectedVariants: selectedVariants,
      barcode: compact.barcode,
      lotNumber: compact.lotNumber,
      // ⚡ Usar valores en caché para carga instantánea
      cachedProductName: compact.productName,
      cachedSku: compact.sku,
      // ⚡ product y resolvedVariant se cargarán bajo demanda si es necesario
    );
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength);
  }
}
