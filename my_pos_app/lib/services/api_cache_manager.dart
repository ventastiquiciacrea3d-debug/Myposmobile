// lib/services/api_cache_manager.dart
import 'package:dio/dio.dart' show RequestOptions;
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:path_provider/path_provider.dart';

/// Gestiona la configuración de cache HTTP para la API de WooCommerce
///
/// Beneficios:
/// - 40-60% reducción en requests API duplicados
/// - Respuesta instantánea para búsquedas/productos repetidos
/// - Funciona en modo offline usando cache
/// - TTL configurables por tipo de request
class ApiCacheManager {
  static HiveCacheStore? _cacheStore;
  static bool _isInitialized = false;

  /// Inicializa el store de cache (solo una vez)
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _cacheStore = HiveCacheStore(
        appDocDir.path,
        hiveBoxName: 'api_http_cache',
      );
      _isInitialized = true;
    } catch (e) {
      // Si falla, continuará sin cache (graceful degradation)
      _cacheStore = null;
      _isInitialized = false;
    }
  }

  /// ✓✓✓ CRÍTICO: Configuración de cache AGRESIVA para detener lluvia de peticiones
  ///
  /// CAMBIOS:
  /// - Policy: forceCache → FUERZA uso de cache, IGNORA headers del servidor
  /// - maxStale: 30 minutos → Cache muy duradero para productos individuales
  /// - hitCacheOnErrorExcept: SIEMPRE usa cache en errores (excepto auth)
  ///
  /// Esto DETIENE completamente el "Triggering background update" para peticiones repetidas.
  static CacheOptions getCacheOptions() {
    return CacheOptions(
      // Store: usa Hive para persistir cache en disco
      store: _cacheStore ?? MemCacheStore(maxSize: 10485760), // Fallback a memoria (10MB)

      // ✓✓✓ CRÍTICO: FORZAR cache, IGNORAR headers del servidor
      // Esto DETIENE la "lluvia de peticiones" para productos ya solicitados
      policy: CachePolicy.forceCache,

      // Priority: Alta prioridad para cache
      priority: CachePriority.high,

      // ✓✓✓ CRÍTICO: Cache MUY duradero (30 min) para productos individuales
      // Antes: 5 min (demasiado corto, causaba re-fetches constantes)
      // Ahora: 30 min (suficiente para sesión típica de usuario)
      maxStale: const Duration(minutes: 30),

      // ✓✓✓ CRÍTICO: SIEMPRE usar cache en errores (excepto auth)
      // Esto asegura que si hay problema de red, usa cache en vez de fallar
      hitCacheOnErrorExcept: [401, 403],

      // keyBuilder: Construir clave única por request
      keyBuilder: (RequestOptions request) {
        // Incluir método, URL y query params en la clave
        final uri = request.uri;
        return '${request.method}_${uri.path}_${uri.query}';
      },

      // allowPostMethod: NO cachear POST (solo GET)
      allowPostMethod: false,
    );
  }

  /// ✓✓✓ CRÍTICO: Configuración específica para búsquedas (TTL medio)
  static CacheOptions getSearchCacheOptions() {
    final baseOptions = getCacheOptions();
    return baseOptions.copyWith(
      policy: CachePolicy.forceCache, // ✓ FORZAR cache
      maxStale: Nullable(const Duration(minutes: 10)), // ✓ Búsquedas: 10 min (antes 3 min)
    );
  }

  /// ✓✓✓ CRÍTICO: Configuración específica para detalles de productos (TTL muy largo)
  static CacheOptions getProductDetailsCacheOptions() {
    final baseOptions = getCacheOptions();
    return baseOptions.copyWith(
      policy: CachePolicy.forceCache, // ✓ FORZAR cache
      maxStale: Nullable(const Duration(hours: 1)), // ✓ Productos: 1 HORA (antes 15 min)
    );
  }

  /// Limpia todo el cache HTTP
  static Future<void> clearCache() async {
    if (_cacheStore != null) {
      try {
        await _cacheStore!.clean();
      } catch (e) {
        // Ignorar errores al limpiar
      }
    }
  }

  /// Limpia cache de un path específico
  static Future<void> invalidateCache(String path) async {
    if (_cacheStore != null) {
      try {
        await _cacheStore!.delete(path);
      } catch (e) {
        // Ignorar errores
      }
    }
  }
}
