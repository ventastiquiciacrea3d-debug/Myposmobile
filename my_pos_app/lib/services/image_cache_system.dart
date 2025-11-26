// lib/services/image_cache_system.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Sistema de Cache de Imágenes Optimizado
///
/// 3 niveles de cache:
/// 1. LOGOS DE MARCA (50 logos × 2KB = 100KB)
/// 2. IMÁGENES DE PRODUCTO (500 × 5KB = 2.5MB) - LRU
/// 3. THUMBNAILS (1000 × 1KB = 1MB) - LRU
///
/// Optimizaciones:
/// - Formato WebP (80% calidad)
/// - Resize automático (thumbnails: 256x256, producto: 512x512)
/// - LRU eviction automática
/// - Cache persistente en disco
class ImageCacheSystem {
  static ImageCacheSystem? _instance;
  static ImageCacheSystem get instance => _instance ??= ImageCacheSystem._();

  ImageCacheSystem._();

  // Configuración
  static const int maxBrandLogos = 50;
  static const int maxProductImages = 500;
  static const int maxThumbnails = 1000;

  static const int thumbnailSize = 256;
  static const int productImageSize = 512;
  static const int imageQuality = 80; // WebP quality

  // Cache en memoria (LRU)
  final Map<int, Uint8List> _brandLogosCache = <int, Uint8List>{};
  final Map<int, Uint8List> _productImagesCache = <int, Uint8List>{};
  final Map<int, Uint8List> _thumbnailsCache = <int, Uint8List>{};

  // LRU tracking
  final List<int> _productImagesLRU = [];
  final List<int> _thumbnailsLRU = [];

  // Directorios de cache
  Directory? _cacheDir;
  Directory? _brandLogosDir;
  Directory? _productImagesDir;
  Directory? _thumbnailsDir;

  bool _isInitialized = false;

  /// Inicializar sistema de cache
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('[ImageCache] Initializing...');

    final appDocDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDocDir.path}/image_cache');

    // Crear directorios
    _brandLogosDir = Directory('${_cacheDir!.path}/brand_logos');
    _productImagesDir = Directory('${_cacheDir!.path}/products');
    _thumbnailsDir = Directory('${_cacheDir!.path}/thumbnails');

    await _brandLogosDir!.create(recursive: true);
    await _productImagesDir!.create(recursive: true);
    await _thumbnailsDir!.create(recursive: true);

    debugPrint('[ImageCache] ✅ Initialized at: ${_cacheDir!.path}');
    _isInitialized = true;
  }

  // ==================== BRAND LOGOS ====================

  /// Obtener logo de marca
  Future<Uint8List?> getBrandLogo(int brandId, String? logoUrl) async {
    if (!_isInitialized) await initialize();

    // Nivel 1: Memory cache
    if (_brandLogosCache.containsKey(brandId)) {
      debugPrint('[ImageCache] Brand logo $brandId found in memory');
      return _brandLogosCache[brandId];
    }

    // Nivel 2: Disk cache
    final cachedFile = File('${_brandLogosDir!.path}/$brandId.webp');
    if (await cachedFile.exists()) {
      final bytes = await cachedFile.readAsBytes();
      _brandLogosCache[brandId] = bytes;
      debugPrint('[ImageCache] Brand logo $brandId loaded from disk');
      return bytes;
    }

    // Nivel 3: Download
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return await _downloadAndCacheBrandLogo(brandId, logoUrl);
    }

    return null;
  }

  Future<Uint8List?> _downloadAndCacheBrandLogo(int brandId, String url) async {
    try {
      debugPrint('[ImageCache] Downloading brand logo: $url');

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('[ImageCache] Failed to download: ${response.statusCode}');
        return null;
      }

      // Comprimir a WebP
      final compressed = await FlutterImageCompress.compressWithList(
        response.bodyBytes,
        quality: imageQuality,
        format: CompressFormat.webp,
      );

      // Guardar en disco
      final file = File('${_brandLogosDir!.path}/$brandId.webp');
      await file.writeAsBytes(compressed);

      // Guardar en memoria
      _brandLogosCache[brandId] = compressed;

      debugPrint('[ImageCache] ✅ Brand logo cached: ${compressed.length} bytes');
      return compressed;

    } catch (e) {
      debugPrint('[ImageCache] ❌ Error downloading brand logo: $e');
      return null;
    }
  }

  // ==================== PRODUCT IMAGES ====================

  /// Obtener imagen de producto
  Future<Uint8List?> getProductImage(int productId, String? imageUrl) async {
    if (!_isInitialized) await initialize();

    // Nivel 1: Memory cache
    if (_productImagesCache.containsKey(productId)) {
      _updateLRU(_productImagesLRU, productId);
      debugPrint('[ImageCache] Product image $productId found in memory');
      return _productImagesCache[productId];
    }

    // Nivel 2: Disk cache
    final cachedFile = File('${_productImagesDir!.path}/$productId.webp');
    if (await cachedFile.exists()) {
      final bytes = await cachedFile.readAsBytes();
      _addToProductCache(productId, bytes);
      debugPrint('[ImageCache] Product image $productId loaded from disk');
      return bytes;
    }

    // Nivel 3: Download
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return await _downloadAndCacheProductImage(productId, imageUrl);
    }

    return null;
  }

  Future<Uint8List?> _downloadAndCacheProductImage(int productId, String url) async {
    try {
      debugPrint('[ImageCache] Downloading product image: $url');

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      // Comprimir y resize a 512x512
      final compressed = await FlutterImageCompress.compressWithList(
        response.bodyBytes,
        minWidth: productImageSize,
        minHeight: productImageSize,
        quality: imageQuality,
        format: CompressFormat.webp,
      );

      // Guardar en disco
      final file = File('${_productImagesDir!.path}/$productId.webp');
      await file.writeAsBytes(compressed);

      // Agregar a cache con LRU
      _addToProductCache(productId, compressed);

      debugPrint('[ImageCache] ✅ Product image cached: ${compressed.length} bytes');
      return compressed;

    } catch (e) {
      debugPrint('[ImageCache] ❌ Error downloading product image: $e');
      return null;
    }
  }

  // ==================== THUMBNAILS ====================

  /// Obtener thumbnail de producto
  Future<Uint8List?> getThumbnail(int productId, String? imageUrl) async {
    if (!_isInitialized) await initialize();

    // Nivel 1: Memory cache
    if (_thumbnailsCache.containsKey(productId)) {
      _updateLRU(_thumbnailsLRU, productId);
      debugPrint('[ImageCache] Thumbnail $productId found in memory');
      return _thumbnailsCache[productId];
    }

    // Nivel 2: Disk cache
    final cachedFile = File('${_thumbnailsDir!.path}/$productId.webp');
    if (await cachedFile.exists()) {
      final bytes = await cachedFile.readAsBytes();
      _addToThumbnailCache(productId, bytes);
      debugPrint('[ImageCache] Thumbnail $productId loaded from disk');
      return bytes;
    }

    // Nivel 3: Download
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return await _downloadAndCacheThumbnail(productId, imageUrl);
    }

    return null;
  }

  Future<Uint8List?> _downloadAndCacheThumbnail(int productId, String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      // Comprimir y resize a 256x256
      final compressed = await FlutterImageCompress.compressWithList(
        response.bodyBytes,
        minWidth: thumbnailSize,
        minHeight: thumbnailSize,
        quality: imageQuality,
        format: CompressFormat.webp,
      );

      // Guardar en disco
      final file = File('${_thumbnailsDir!.path}/$productId.webp');
      await file.writeAsBytes(compressed);

      // Agregar a cache con LRU
      _addToThumbnailCache(productId, compressed);

      debugPrint('[ImageCache] ✅ Thumbnail cached: ${compressed.length} bytes');
      return compressed;

    } catch (e) {
      debugPrint('[ImageCache] ❌ Error downloading thumbnail: $e');
      return null;
    }
  }

  // ==================== LRU MANAGEMENT ====================

  void _addToProductCache(int productId, Uint8List bytes) {
    // Evict si está lleno
    if (_productImagesCache.length >= maxProductImages && !_productImagesCache.containsKey(productId)) {
      _evictLRU(_productImagesLRU, _productImagesCache, _productImagesDir!);
    }

    _productImagesCache[productId] = bytes;
    _updateLRU(_productImagesLRU, productId);
  }

  void _addToThumbnailCache(int productId, Uint8List bytes) {
    if (_thumbnailsCache.length >= maxThumbnails && !_thumbnailsCache.containsKey(productId)) {
      _evictLRU(_thumbnailsLRU, _thumbnailsCache, _thumbnailsDir!);
    }

    _thumbnailsCache[productId] = bytes;
    _updateLRU(_thumbnailsLRU, productId);
  }

  void _updateLRU(List<int> lru, int id) {
    lru.remove(id);
    lru.add(id);
  }

  void _evictLRU(List<int> lru, Map<int, Uint8List> cache, Directory dir) {
    if (lru.isEmpty) return;

    final evictId = lru.removeAt(0);
    cache.remove(evictId);

    // Eliminar archivo de disco (opcional)
    final file = File('${dir.path}/$evictId.webp');
    file.delete().catchError((_) {});

    debugPrint('[ImageCache] Evicted $evictId from cache');
  }

  // ==================== CLEANUP ====================

  /// Limpiar cache (eliminar imágenes antiguas)
  Future<int> cleanup({int olderThanDays = 30}) async {
    if (!_isInitialized) return 0;

    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    int deletedCount = 0;

    // Limpiar cada directorio
    for (final dir in [_brandLogosDir!, _productImagesDir!, _thumbnailsDir!]) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
            deletedCount++;
          }
        }
      }
    }

    // Limpiar memory cache
    _productImagesCache.clear();
    _thumbnailsCache.clear();
    _productImagesLRU.clear();
    _thumbnailsLRU.clear();

    debugPrint('[ImageCache] 🧹 Cleaned up $deletedCount images');
    return deletedCount;
  }

  /// Obtener estadísticas
  Future<Map<String, dynamic>> getStats() async {
    if (!_isInitialized) return {};

    int totalSize = 0;
    int totalFiles = 0;

    for (final dir in [_brandLogosDir!, _productImagesDir!, _thumbnailsDir!]) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          totalSize += await entity.length();
          totalFiles++;
        }
      }
    }

    return {
      'brand_logos_memory': _brandLogosCache.length,
      'product_images_memory': _productImagesCache.length,
      'thumbnails_memory': _thumbnailsCache.length,
      'total_files_disk': totalFiles,
      'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
    };
  }
}
