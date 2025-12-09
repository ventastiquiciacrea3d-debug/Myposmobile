// lib/services/product_converter_service.dart
import '../models/product.dart';
import '../models/product_optimized.dart';
import '../services/database_service.dart';
import '../models/dictionaries.dart';
import '../objectbox.g.dart'; // Para query builders
import '../utils/product_attribute_serializer.dart';

/// Servicio para convertir entre Product (legacy Hive) y ProductOptimized (ObjectBox)
class ProductConverterService {
  final DatabaseService _db;

  ProductConverterService(this._db);

  /// Convertir Product (Hive) a ProductOptimized (ObjectBox)
  ProductOptimized productToOptimized(Product product) {
    // Extraer IDs de diccionarios
    final brandId = _getOrCreateBrandId(_extractBrandFromName(product.name));
    final categoryId = _getOrCreateCategoryId(product.categoryNames?.first ?? 'Uncategorized');

    // Parsear IDs
    final int productId = int.tryParse(product.id) ?? 0;
    final int parentId = product.parentId ?? 0;

    // Precio en centavos
    final int priceInCents = (product.price * 100).round();
    final int specialPriceInCents = product.salePrice != null ? (product.salePrice! * 100).round() : 0;

    // Stock
    final int stockQuantity = product.stockQuantity ?? 0;
    final int stockStatus = _parseStockStatus(product.stockStatus);

    // Tipo de producto
    final int productType = _parseProductType(product.type);

    // Flags
    int flags = 0;
    if (product.manageStock) flags |= 0x01;
    if (product.onSale) flags |= 0x02;
    // Bit 2 (featured) - no tenemos en Product original
    // Bit 3 (virtual) - no tenemos en Product original
    // Bit 4 (downloadable) - no tenemos en Product original

    return ProductOptimized(
      id: productId,
      brandId: brandId,
      categoryId: categoryId,
      parentId: parentId,
      imageId: 0, // TODO: Implementar cache de imágenes
      name: _truncate(product.name, 40),
      sku: product.sku.isNotEmpty ? _truncate(product.sku, 15) : null,
      barcode: product.barcode?.isNotEmpty == true ? _truncate(product.barcode!, 13) : null,
      variantSku: null,
      priceInCents: priceInCents,
      specialPriceInCents: specialPriceInCents,
      stockQuantity: stockQuantity,
      attributesCompressed: ProductAttributeSerializer.compressBoth(
        attributes: product.attributes,
        fullAttributesWithOptions: product.fullAttributesWithOptions,
      ),
      lastUpdated: DateTime.now(),
      productType: productType,
      stockStatus: stockStatus,
      flags: flags,
    );
  }

  /// Convertir ProductOptimized (ObjectBox) a Product (Hive)
  Product optimizedToProduct(ProductOptimized optimized) {
    // Obtener category de diccionarios
    final category = _getCategoryName(optimized.categoryId);

    // ✅ Descomprimir atributos desde ObjectBox
    final decompressed = ProductAttributeSerializer.decompressBoth(
      optimized.attributesCompressed,
    );

    return Product(
      id: optimized.id.toString(),
      name: optimized.name,
      sku: optimized.sku ?? '',
      price: optimized.price,
      salePrice: optimized.specialPrice,
      stockStatus: optimized.stockStatusString,
      stockQuantity: optimized.stockQuantity,
      manageStock: optimized.managingStock,
      type: optimized.typeString,
      parentId: optimized.parentId > 0 ? optimized.parentId : null,
      barcode: optimized.barcode,
      categoryNames: category.isNotEmpty ? [category] : null,
      onSale: optimized.isOnSale,
      thumbnailUrl: null, // TODO: Obtener de image cache
      // ✅ MIGRACIÓN COMPLETADA: Atributos ahora vienen desde ObjectBox
      attributes: decompressed['attributes'],
      fullAttributesWithOptions: decompressed['fullAttributesWithOptions'],
    );
  }

  // ==================== HELPERS PRIVADOS ====================

  int _getOrCreateBrandId(String brandName) {
    final brandBox = _db.store.box<BrandDictionary>();

    // Buscar existente
    final query = brandBox.query(BrandDictionary_.name.equals(brandName)).build();
    BrandDictionary? brand = query.findFirst();
    query.close();

    if (brand != null) {
      return brand.id;
    }

    // ⚡ FIX: Intentar crear, pero manejar race condition
    try {
      // Crear nuevo
      brand = BrandDictionary(name: brandName, logoFilename: null);
      brandBox.put(brand);
      return brand.id;
    } catch (e) {
      // ⚡ FIX: Si falla (posible constraint violation por race condition),
      // buscar de nuevo - otro thread pudo haber creado la marca
      final retryQuery = brandBox.query(BrandDictionary_.name.equals(brandName)).build();
      brand = retryQuery.findFirst();
      retryQuery.close();

      if (brand != null) {
        return brand.id;
      }

      // Si aún no existe, re-lanzar el error original
      rethrow;
    }
  }

  int _getOrCreateCategoryId(String categoryName) {
    // TODO: Implementar CategoryDictionary cuando se agregue al modelo
    // Por ahora retornar 0
    return 0;
  }

  String _getBrandName(int brandId) {
    if (brandId == 0) return 'Unknown';

    final brandBox = _db.store.box<BrandDictionary>();
    final brand = brandBox.get(brandId);
    return brand?.name ?? 'Unknown';
  }

  String _getCategoryName(int categoryId) {
    if (categoryId == 0) return 'Uncategorized';
    // TODO: Implementar CategoryDictionary cuando se agregue al modelo
    return 'Uncategorized';
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength);
  }

  static int _parseStockStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'instock':
        return 1;
      case 'onbackorder':
        return 2;
      case 'outofstock':
      default:
        return 0;
    }
  }

  static int _parseProductType(String type) {
    switch (type.toLowerCase()) {
      case 'variable':
        return 1;
      case 'variation':
        return 2;
      case 'simple':
      default:
        return 0;
    }
  }

  static String _extractBrandFromName(String name) {
    // Extraer marca del nombre (primer palabra generalmente)
    final parts = name.split(' ');
    return parts.isNotEmpty ? parts[0] : 'Unknown';
  }
}
