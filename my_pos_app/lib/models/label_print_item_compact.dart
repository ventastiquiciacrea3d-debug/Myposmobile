// lib/models/label_print_item_compact.dart
import 'package:objectbox/objectbox.dart';

/// LabelPrintItem Compacto para ObjectBox: ~80 bytes
///
/// Solo guarda lo esencial para la cola de impresión
@Entity()
class LabelPrintItemCompact {
  // ObjectBox ID (auto-increment)
  @Id()
  int localId = 0;

  // ==================== IDs (12 bytes) ====================

  /// UUID del item
  @Index()
  @Unique()
  String itemId;

  /// Product ID
  @Index()
  int productId;

  /// Variation ID (0 si no es variación)
  int variationId;

  // ==================== STRINGS (50 bytes) ====================

  /// Nombre del producto (max 50 chars)
  String productName;

  /// SKU (max 20 chars)
  String sku;

  /// Barcode (max 13 chars)
  String? barcode;

  /// Brand (max 30 chars)
  String? brand;

  /// Variant text (max 50 chars) - ej: "Color: Rojo, Talla: M"
  String? variantText;

  /// Lot number (max 20 chars)
  String? lotNumber;

  // ==================== METADATA (12 bytes) ====================

  /// Cantidad de etiquetas a imprimir
  int quantity;

  /// Fecha para la etiqueta
  @Property(type: PropertyType.date)
  DateTime? labelDate;

  /// Fecha de creación del item en cola
  @Property(type: PropertyType.date)
  DateTime createdAt;

  /// Flags (8 bits)
  /// Bit 0: isPrinted
  /// Bit 1-7: Reservados
  int flags;

  // ==================== CONSTRUCTOR ====================

  LabelPrintItemCompact({
    required this.itemId,
    required this.productId,
    required this.variationId,
    required this.productName,
    required this.sku,
    this.barcode,
    this.brand,
    this.variantText,
    this.lotNumber,
    required this.quantity,
    this.labelDate,
    required this.createdAt,
    required this.flags,
  });

  // ==================== GETTERS HELPERS ====================

  bool get isPrinted => (flags & 0x01) != 0;

  // ==================== SETTERS HELPERS ====================

  set isPrinted(bool value) {
    if (value) {
      flags |= 0x01;
    } else {
      flags &= ~0x01;
    }
  }

  // ==================== TO STRING ====================

  @override
  String toString() {
    return 'LabelPrintItemCompact(name: $productName, sku: $sku, qty: $quantity, printed: $isPrinted)';
  }
}
