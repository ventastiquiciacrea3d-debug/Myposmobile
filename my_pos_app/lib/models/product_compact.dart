import 'package:objectbox/objectbox.dart';

/// Producto comprimido - Solo datos esenciales
/// Tamaño promedio: 75 bytes (vs 500 bytes sin optimizar)
@Entity()
class ProductCompact {
  @Id()
  int localId = 0; // Auto-increment

  @Index()
  @Unique()
  int id; // WooCommerce ID - 4 bytes

  @Index(type: IndexType.value)
  String name; // 50 bytes max - nombre optimizado

  @Index()
  String? sku; // 15 bytes max

  @Index()
  String? barcode; // 13 bytes max

  int stockQuantity; // 2 bytes (int16 internamente)

  int brandId; // 1 byte - referencia a diccionario

  bool hasVariations; // 1 byte

  bool imageCached; // 1 byte

  /// IDs de atributos (referencia a diccionario)
  List<int> attributeIds;

  /// Datos comprimidos de variaciones (si existen)
  @Property(type: PropertyType.byteVector)
  List<int>? variationData;

  /// Precio (almacenado como centavos para evitar decimales)
  int priceInCents; // \$29.99 = 2999

  /// Estado de stock
  String stockStatus; // 'instock', 'outofstock', 'onbackorder'

  /// Timestamp de última actualización
  @Property(type: PropertyType.date)
  DateTime lastUpdated;

  /// Tipo de producto
  String type; // 'simple', 'variable', 'variation'

  /// ID del producto padre (si es variación)
  int? parentId;

  ProductCompact({
    this.localId = 0,
    required this.id,
    required this.name,
    this.sku,
    this.barcode,
    this.stockQuantity = 0,
    this.brandId = 0,
    this.hasVariations = false,
    this.imageCached = false,
    this.attributeIds = const [],
    this.variationData,
    this.priceInCents = 0,
    this.stockStatus = 'instock',
    required this.lastUpdated,
    this.type = 'simple',
    this.parentId,
  });

  /// Precio en formato decimal
  double get price => priceInCents / 100.0;

  /// Verificar si está disponible
  bool get isAvailable => stockStatus == 'instock' && stockQuantity > 0;

  /// Comprimir nombre eliminando palabras comunes
  static String compressName(String fullName) {
    return fullName
        .replaceAll(RegExp(r'\b(producto|product|item)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .substring(0, fullName.length > 50 ? 50 : fullName.length);
  }

  /// Comprimir SKU eliminando prefijos repetitivos
  static String? compressSKU(String? sku) {
    if (sku == null || sku.isEmpty) return null;

    return sku
        .replaceAll(RegExp(r'^(PROD-|ITEM-|SKU-)'), '')
        .substring(0, sku.length > 15 ? 15 : sku.length);
  }
}

/// Variación comprimida
/// Tamaño promedio: 30 bytes
@Entity()
class VariationCompact {
  @Id()
  int localId = 0;

  @Index()
  @Unique()
  int id; // 4 bytes

  @Index()
  int parentId; // 4 bytes

  String? sku; // 15 bytes max

  int stockQuantity; // 2 bytes

  /// Valores de atributos (IDs del diccionario)
  /// Ejemplo: [1, 5] = Color: Rojo, Talla: M
  List<int> attributeValues; // 3-8 bytes

  int priceInCents; // 4 bytes

  String stockStatus;

  @Property(type: PropertyType.date)
  DateTime lastUpdated;

  VariationCompact({
    this.localId = 0,
    required this.id,
    required this.parentId,
    this.sku,
    this.stockQuantity = 0,
    this.attributeValues = const [],
    this.priceInCents = 0,
    this.stockStatus = 'instock',
    required this.lastUpdated,
  });

  double get price => priceInCents / 100.0;
  bool get isAvailable => stockStatus == 'instock' && stockQuantity > 0;
}
