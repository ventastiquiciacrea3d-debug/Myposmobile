// lib/services/woocommerce_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

import '../models/product.dart';
import '../models/order.dart';
import '../models/inventory_movement.dart';
import 'storage_service.dart';
import 'connectivity_service.dart';
import 'dio_retry_interceptor.dart';
import 'api_cache_manager.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

// --- Excepciones ---
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => 'ApiException: $message ${statusCode != null ? "(Status: $statusCode)" : ""}';
}
class NetworkException extends ApiException { NetworkException(String message) : super("Error de Red: $message"); }
class AuthenticationException extends ApiException { AuthenticationException(String message) : super("Error de Autenticación: $message"); }
class ServerException extends ApiException { ServerException(String message, {int? statusCode}) : super("Error del Servidor: $message", statusCode: statusCode); }
class ProductNotFoundException extends ApiException { ProductNotFoundException(String identifier) : super("Producto no encontrado con identificador: $identifier", statusCode: 404); }
class VariationNotFoundException extends ApiException { VariationNotFoundException(String productId, Map<String, String> attributes) : super("Variación no encontrada para producto $productId con atributos: $attributes", statusCode: 404); }
class OrderNotFoundException extends ApiException { OrderNotFoundException(String orderId) : super('Pedido con ID $orderId no encontrado.', statusCode: 404); }
class InvalidDataException implements Exception {
  final String message;
  InvalidDataException(this.message);
  @override
  String toString() => 'InvalidDataException: $message';
}

class WooCommerceService {
  final StorageService _storageService;
  final ConnectivityService _connectivityService;
  Dio _dio = Dio();
  String? _apiUrl;
  bool _isInitialized = false;
  bool _isTestingConnection = false;

  // --- Lógica de Refresco de Token ---
  bool _isRefreshingToken = false;
  Completer<void>? _tokenRefreshCompleter;

  String get connectionMode => _storageService.getConnectionMode();
  bool get isServiceInitialized => _isInitialized;

  WooCommerceService({
    required StorageService storageService,
    required ConnectivityService connectivityService,
  })  : _storageService = storageService,
        _connectivityService = connectivityService {
    debugPrint("[WooCommerceService] Instanciado.");
  }

  Future<Dio> _getDioClient() async {
    if (!_isInitialized) {
      await initializeDioClient();
      if (!_isInitialized) {
        throw AuthenticationException("Cliente API no inicializado o credenciales inválidas. Verifica la configuración.");
      }
    }
    return _dio;
  }

  Future<void> initializeDioClient() async {
    _apiUrl = await _storageService.getApiUrl();

    if (_apiUrl != null && _apiUrl!.isNotEmpty) {
      String sanitizedUrl = _apiUrl!.trim();
      if (!sanitizedUrl.endsWith('/')) { sanitizedUrl += '/'; }
      if (!sanitizedUrl.startsWith('http://') && !sanitizedUrl.startsWith('https://')) { sanitizedUrl = 'https://$sanitizedUrl'; }

      try { Uri.parse(sanitizedUrl); }
      catch (e) {
        _isInitialized = false;
        throw InvalidDataException("Formato de URL de la tienda inválido.");
      }

      // ✓✓✓ CRÍTICO: Configuración de timeouts EXPLÍCITA
      final baseOptions = BaseOptions(
        baseUrl: sanitizedUrl,
        connectTimeout: const Duration(seconds: 15), // ✓ OPTIMIZADO: Reducido de 20s
        receiveTimeout: const Duration(seconds: 30), // ✓ OPTIMIZADO: Reducido de 120s
        sendTimeout: const Duration(seconds: 15),     // ✓ OPTIMIZADO: Agregado
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', 'User-Agent': 'MyPOSMobileBarcode/3.1.0', },
        responseType: ResponseType.plain,
      );

      _dio = Dio(baseOptions);

      // ✓✓✓ CRÍTICO: Logging para verificar que timeouts se aplican
      debugPrint("[WooCommerceService] Timeouts configurados:");
      debugPrint("  connectTimeout: ${_dio.options.connectTimeout}");
      debugPrint("  receiveTimeout: ${_dio.options.receiveTimeout}");
      debugPrint("  sendTimeout: ${_dio.options.sendTimeout}");

      _dio.interceptors.clear();

      // ✓ OPTIMIZADO: Cache interceptor PRIMERO (máxima prioridad)
      _dio.interceptors.add(DioCacheInterceptor(
        options: ApiCacheManager.getCacheOptions(),
      ));

      // ✓ OPTIMIZADO: Retry interceptor SEGUNDO (después de cache, antes de auth)
      _dio.interceptors.add(RetryInterceptor(
        dio: _dio,
        maxRetries: 3,
        initialDelay: const Duration(seconds: 1),
      ));

      // Auth interceptor ÚLTIMO
      _dio.interceptors.add(_createAuthInterceptor());

      if (kDebugMode) {
        _dio.interceptors.add(LogInterceptor( requestBody: true, responseBody: true, requestHeader: true, responseHeader: false, error: true, logPrint: (obj) => debugPrint(obj.toString()) ));
      }

      final String? accessToken = await _storageService.getAccessToken();
      final String? cKey = await _storageService.getConsumerKey();

      _isInitialized = (connectionMode == 'plugin' && accessToken != null && accessToken.isNotEmpty) ||
          (connectionMode != 'plugin' && cKey != null && cKey.isNotEmpty);

      debugPrint("[WooCommerceService.initializeDioClient] Cliente Dio INICIALIZADO. Modo: $connectionMode. IsInitialized: $_isInitialized");
    } else {
      _isInitialized = false;
      debugPrint("[WooCommerceService.initializeDioClient] Cliente Dio NO INICIALIZADO - URL o credenciales faltantes.");
    }
  }

  QueuedInterceptorsWrapper _createAuthInterceptor() {
    return QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        // Rutas públicas que no necesitan token de acceso
        if (options.path.contains('mypos/v1/register-device') || options.path.contains('mypos/v1/refresh-token')) {
          return handler.next(options);
        }

        if (connectionMode == 'plugin') {
          // Si ya se está refrescando un token, espera a que termine
          if (_isRefreshingToken) {
            await _tokenRefreshCompleter?.future;
          }
          final accessToken = await _storageService.getAccessToken();
          if (accessToken != null && accessToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          } else {
            // Si no hay token, rechaza la petición. Esto podría pasar si el refresco falla.
            return handler.reject(DioException(requestOptions: options, error: "Token de acceso no encontrado."));
          }
        } else { // Modo WooCommerce Legacy
          final cKey = await _storageService.getConsumerKey();
          final cSecret = await _storageService.getConsumerSecret();
          if (cKey != null && cSecret != null) {
            options.queryParameters['consumer_key'] = cKey;
            options.queryParameters['consumer_secret'] = cSecret;
          } else {
            return handler.reject(DioException(requestOptions: options, error: "Credenciales de WooCommerce no encontradas."));
          }
        }
        return handler.next(options);
      },
      onError: (e, handler) async {
        // Si la petición falla con 401 (No autorizado) y estamos en modo plugin, intentamos refrescar el token.
        if (e.response?.statusCode == 401 && connectionMode == 'plugin' && !_isRefreshingToken) {
          debugPrint("[Dio Interceptor] Token de acceso expirado o inválido. Intentando refrescar...");
          _isRefreshingToken = true;
          _tokenRefreshCompleter = Completer<void>();

          try {
            await _refreshToken();
            // Una vez refrescado, reintentamos la petición original.
            final response = await _dio.request(
              e.requestOptions.path,
              data: e.requestOptions.data,
              queryParameters: e.requestOptions.queryParameters,
              options: Options(method: e.requestOptions.method, headers: e.requestOptions.headers),
            );
            _isRefreshingToken = false;
            _tokenRefreshCompleter?.complete();
            return handler.resolve(response); // Resolvemos con la nueva respuesta exitosa.
          } catch (refreshError) {
            debugPrint("[Dio Interceptor] Falló el refresco del token: $refreshError");
            _isRefreshingToken = false;
            _tokenRefreshCompleter?.complete();
            // Si el refresco falla, se propaga el error original (401) para que la UI pueda manejarlo.
            return handler.next(e);
          }
        }
        return handler.next(e);
      },
    );
  }

  Future<void> _refreshToken() async {
    final refreshToken = await _storageService.getRefreshToken();
    if (refreshToken == null) {
      _isInitialized = false;
      throw AuthenticationException("No hay token de refresco disponible. Se requiere vincular de nuevo.");
    }

    // ⚡ FIX: Obtener URL de storage para mayor robustez
    final String? apiUrl = await _storageService.getApiUrl();
    if (apiUrl == null || apiUrl.isEmpty) {
      throw AuthenticationException("URL de la API no configurada.");
    }

    String sanitizedUrl = apiUrl.trim();
    if (!sanitizedUrl.endsWith('/')) { sanitizedUrl += '/'; }
    if (!sanitizedUrl.startsWith('http://') && !sanitizedUrl.startsWith('https://')) {
      sanitizedUrl = 'https://$sanitizedUrl';
    }

    try {
      // ⚡ FIX: Usar apiUrl desde storage en lugar de _dio.options.baseUrl
      final tempDio = Dio(BaseOptions(baseUrl: sanitizedUrl, responseType: ResponseType.plain));
      final response = await tempDio.post(
        'wp-json/mypos/v1/refresh-token',
        data: {'refresh_token': refreshToken},
      );
      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic> && data['access_token'] != null && data['refresh_token'] != null) {
        await _storageService.saveAccessToken(data['access_token']);
        await _storageService.saveRefreshToken(data['refresh_token']);
        debugPrint("[_refreshToken] Tokens refrescados exitosamente.");
      } else {
        throw AuthenticationException("Respuesta inválida del endpoint de refresco de token.");
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _storageService.clearApiCredentials();
        _isInitialized = false;
      }
      _handleDioError(e, "refrescar token", throwException: true);
    }
  }

  Future<void> registerDeviceWithPlugin() async {
    if (connectionMode != 'plugin') throw ApiException("El registro de dispositivo solo es válido en modo plugin.");

    final String? apiUrl = await _storageService.getApiUrl();
    final String? masterApiKey = await _storageService.getMyPosApiKey();
    final String deviceUuid = await _storageService.getOrCreateDeviceUuid();
    final String deviceName = "POS Flutter ${deviceUuid.substring(0, 8)}";

    if (apiUrl == null || masterApiKey == null) {
      throw AuthenticationException("URL de la API o Clave Maestra del Plugin no configuradas.");
    }

    // ⚡ FIX: Sanitizar la URL antes de usarla
    String sanitizedUrl = apiUrl.trim();
    if (!sanitizedUrl.endsWith('/')) { sanitizedUrl += '/'; }
    if (!sanitizedUrl.startsWith('http://') && !sanitizedUrl.startsWith('https://')) {
      sanitizedUrl = 'https://$sanitizedUrl';
    }

    try {
      // ⚡ FIX: Usar apiUrl desde storage en lugar de _dio.options.baseUrl
      // Esto permite que funcione antes de que initializeDioClient() sea llamado
      final tempDio = Dio(BaseOptions(baseUrl: sanitizedUrl, responseType: ResponseType.plain));
      final response = await tempDio.post(
          'wp-json/mypos/v1/register-device',
          data: {
            'api_key': masterApiKey,
            'device_uuid': deviceUuid,
            'device_name': deviceName,
          }
      );

      final data = _tryParseResponseData(response);

      // ✓ DEBUG: Logging detallado para diagnosticar el formato de respuesta
      debugPrint("[registerDeviceWithPlugin] Response status: ${response.statusCode}");
      debugPrint("[registerDeviceWithPlugin] Response data type: ${data.runtimeType}");
      debugPrint("[registerDeviceWithPlugin] Response data: $data");

      // --- INICIO DE LA CORRECCIÓN ---
      // Añade compatibilidad con la respuesta 'jwt' (antigua) y 'access_token' (nueva).
      if (data is Map<String, dynamic>) {
        String? accessToken = data['access_token']?.toString();
        String? refreshToken = data['refresh_token']?.toString();

        // Fallback: Si no se encuentran los tokens nuevos, buscar el token 'jwt' antiguo.
        if (accessToken == null && data['jwt'] != null) {
          accessToken = data['jwt']?.toString();
          refreshToken = data['jwt']?.toString(); // Usar el mismo token para ambos
          debugPrint("[registerDeviceWithPlugin] Fallback: Usando 'jwt' de una versión anterior del plugin.");
        }

        if (accessToken != null && accessToken.isNotEmpty && refreshToken != null && refreshToken.isNotEmpty) {
          await _storageService.saveAccessToken(accessToken);
          await _storageService.saveRefreshToken(refreshToken);
          debugPrint("[registerDeviceWithPlugin] Tokens guardados exitosamente");
          await initializeDioClient();
        } else {
          // El error ahora es más específico si falla la lógica de fallback
          debugPrint("[registerDeviceWithPlugin] ERROR: No se encontraron 'access_token' ni 'jwt' en la respuesta.");
          throw AuthenticationException("La respuesta de registro no contiene tokens válidos. Verifica que el plugin esté actualizado en WordPress (v3.0.1+).");
        }
      } else {
        // Esto maneja el caso de que 'data' no sea un Map
        debugPrint("[registerDeviceWithPlugin] ERROR: La respuesta del servidor no es un objeto JSON válido.");
        throw AuthenticationException("La respuesta del servidor no fue un objeto JSON válido.");
      }
      // --- FIN DE LA CORRECCIÓN ---

    } on DioException catch (e) {
      _handleDioError(e, "registrar dispositivo", throwException: true);
    }
  }

  // --- El resto de los métodos no han cambiado en su lógica fundamental ---

  dynamic _tryParseResponseData(Response response) {
    if (response.data == null) return (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) ? {} : null;
    if (response.data is Map || response.data is List) return response.data;
    if (response.data is String) {
      try {
        final trimmedData = (response.data as String).trim();
        if (trimmedData.isEmpty) return (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) ? {} : null;
        if (trimmedData.startsWith('<')) {
          final titleRegex = RegExp(r'<title>(.*?)<\/title>');
          final match = titleRegex.firstMatch(trimmedData);
          if (match != null && match.group(1) != null) {
            final serverMessage = match.group(1)!.trim();
            if(serverMessage.toLowerCase().contains('page not found') || response.statusCode == 404){
              throw ServerException("No se ha encontrado ninguna ruta que coincida con la URL y el método de la solicitud.", statusCode: 404);
            }
            throw InvalidDataException("Respuesta inesperada del servidor (HTML): $serverMessage");
          }
          throw InvalidDataException("Respuesta inesperada del servidor (formato HTML).");
        }
        return jsonDecode(trimmedData);
      } catch (e) {
        if(e is ApiException) rethrow;
        throw InvalidDataException("Error al procesar respuesta JSON: $e");
      }
    }
    throw InvalidDataException("Tipo de datos de respuesta inesperado: ${response.data.runtimeType}.");
  }

  String _handleDioError(DioException e, String context, {bool throwException = true}) {
    String errorMessage = "Error desconocido procesando la solicitud en [$context].";
    int? statusCode = e.response?.statusCode;
    String serverMsg = "";

    if (e.response?.data != null) {
      try {
        dynamic errorData;
        if (e.response!.data is String) {
          errorData = _tryParseResponseData(e.response!);
        } else {
          errorData = e.response!.data;
        }

        if (errorData is Map) {
          serverMsg = errorData['message']?.toString() ?? jsonEncode(errorData);
        } else if (errorData is String) {
          if (errorData.startsWith('{')) {
            final decoded = jsonDecode(errorData);
            serverMsg = decoded['message'] ?? errorData;
          } else if (errorData.startsWith('<')) {
            final titleRegex = RegExp(r'<title>(.*?)<\/title>');
            final match = titleRegex.firstMatch(errorData);
            serverMsg = (match != null && match.group(1) != null) ? match.group(1)!.trim() : 'Respuesta de error en formato HTML';
          } else {
            serverMsg = errorData;
          }
        } else {
          serverMsg = e.response?.data.toString() ?? 'Respuesta de error sin formato esperado';
        }
      } catch (parseError) {
        if (parseError is ApiException) {
          if(throwException) rethrow;
          errorMessage = parseError.message;
        }
        serverMsg = e.response?.data?.toString() ?? 'Error al parsear detalles del error';
      }
      serverMsg = serverMsg.trim().replaceAll(RegExp(r'<[^>]*>'), '');
      if (serverMsg.length > 250) serverMsg = "${serverMsg.substring(0, 247)}...";
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        errorMessage = "Tiempo de espera agotado conectando con el servidor.";
        if (throwException) throw NetworkException(errorMessage);
        break;
      case DioExceptionType.badResponse:
        switch (statusCode) {
          case 401: case 403:
          errorMessage = "Credenciales API inválidas o permisos insuficientes. ${serverMsg.isNotEmpty ? serverMsg : ''}";
          _isInitialized = false;
          if (throwException) throw AuthenticationException(errorMessage);
          break;
          case 404:
            errorMessage = "No se ha encontrado ninguna ruta que coincida con la URL y el método de la solicitud.";
            if (throwException) throw ServerException(errorMessage, statusCode: statusCode);
            break;
          case 522:
            errorMessage = "El servidor (Host) tardó demasiado en responder (Error 522). Contacta a tu proveedor de hosting.";
            if (throwException) throw ServerException(errorMessage, statusCode: statusCode);
            break;
          default:
            errorMessage = "Error en la respuesta del servidor (Status $statusCode): ${serverMsg.isNotEmpty ? serverMsg : e.message ?? 'Desconocido'}";
            if (throwException) throw ServerException(errorMessage, statusCode: statusCode);
            break;
        }
        break;
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        errorMessage = (e.error is SocketException || e.error is HandshakeException)
            ? "No se pudo conectar al servidor. Verifica tu conexión y la URL."
            : "Error de conexión desconocido: ${e.message ?? e.error?.toString() ?? 'N/A'}";
        if (throwException) throw NetworkException(errorMessage);
        break;
      default:
        errorMessage = "Error inesperado de Dio en [$context]: ${e.message ?? e.type.toString()}";
        if (throwException) throw ApiException(errorMessage);
        break;
    }
    debugPrint("[WCService._handleDioError] Context: $context, Final Error: $errorMessage");
    return errorMessage;
  }

  Future<void> testConnection({ required String apiUrl, required String consumerKey, required String consumerSecret, required String myPosApiKey }) async {
    if (_isTestingConnection) throw ApiException("Prueba de conexión ya en curso.");
    _isTestingConnection = true;

    try {
      if (connectionMode == 'plugin') {
        await _storageService.saveMyPosApiKey(myPosApiKey);
        await registerDeviceWithPlugin();
      } else {
        String testUrl = apiUrl.trim();
        if (!testUrl.endsWith('/')) { testUrl += '/'; }
        if (!testUrl.startsWith('http')) { testUrl = 'https://$testUrl';}
        Uri.parse(testUrl);
        final testEndpoint = '${testUrl}wp-json/wc/v3/system_status';
        final tempDio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
        final response = await tempDio.get(testEndpoint, queryParameters: {'consumer_key': consumerKey.trim(),'consumer_secret': consumerSecret.trim()});
        if (response.statusCode! >= 200 && response.statusCode! < 300) {
          final data = _tryParseResponseData(response);
          if (data is! Map || !data.containsKey('environment')) {
            throw ApiException("Respuesta inesperada del estado del sistema.");
          }
        } else {
          throw ApiException("El servidor respondió con el estado ${response.statusCode}.");
        }
      }
    } on DioException catch (e) {
      _handleDioError(e, "probar conexión", throwException: true);
    } finally {
      _isTestingConnection = false;
    }
  }

  Future<Map<String, dynamic>> _searchProductsWithPluginApi(String query, {int page = 1, int perPage = 10, bool onlyInStock = false}) async {
    if (!_isInitialized) throw AuthenticationException("El servicio API no está inicializado.");
    final dio = await _getDioClient();
    try {
      final response = await dio.get('wp-json/mypos/v1/buscar', queryParameters: {'query': query, 'page': page, 'per_page': perPage, 'only_in_stock': onlyInStock});
      final data = _tryParseResponseData(response);
      if (data is List) {
        final products = data.whereType<Map<String, dynamic>>().map((item) => Product.fromJson(item)).toList();
        final int totalProducts = int.tryParse(response.headers.value('X-WP-Total') ?? '0') ?? 0;
        final int totalPages = int.tryParse(response.headers.value('X-WP-TotalPages') ?? '0') ?? 0;
        return {'products': products, 'total_products': totalProducts, 'total_pages': totalPages};
      }
      throw InvalidDataException("Respuesta inesperada del plugin al buscar '$query'.");
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return {'products': [], 'total_products': 0, 'total_pages': 0};
      _handleDioError(e, "buscar producto via plugin '$query'", throwException: true);
      throw StateError("Unreachable");
    }
  }

  Future<String?> searchProductByBarcodeOrSku(String identifier, {bool useCompute = false, bool searchOnlyAvailable = true}) async {
    if (identifier.trim().isEmpty) return null;
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión para buscar producto.");
    try {
      final resultsMap = await searchProducts(identifier.trim(), limit: 1, searchOnlyAvailable: searchOnlyAvailable);
      final List<Product> results = resultsMap['products'];
      if (results.isEmpty) throw ProductNotFoundException(identifier);

      Product? foundProduct = results.firstWhereOrNull((p) =>
      p.sku.toLowerCase() == identifier.trim().toLowerCase() || (p.barcode?.toLowerCase() == identifier.trim().toLowerCase())
      ) ?? results.first;

      return await getProductById(foundProduct.id, useCompute: useCompute);

    } catch (e) {
      if (e is ProductNotFoundException) rethrow;
      throw ApiException("Error buscando por código: $e");
    }
  }

  Future<Map<String, dynamic>> searchProducts(String query, {int limit = 20, int page = 1, bool searchOnlyAvailable = true}) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión para buscar producto.");

    if (connectionMode == 'plugin') {
      try {
        return await _searchProductsWithPluginApi(query.trim(), page: page, perPage: limit, onlyInStock: searchOnlyAvailable);
      } catch (e) {
        if(e is ApiException) rethrow;
        throw ApiException("Error buscando productos con plugin: $e");
      }
    } else {
      try {
        final dio = await _getDioClient();
        final response = await dio.get('wp-json/wc/v3/products', queryParameters: {
          'search': query.trim(),
          'per_page': limit,
          'page': page,
          'status': 'publish',
          if (searchOnlyAvailable) 'stock_status': 'instock'
        });
        final data = _tryParseResponseData(response);
        if (data is List) {
          final products = data.whereType<Map<String, dynamic>>().map((item) => Product.fromJson(item)).toList();
          final int totalProducts = int.tryParse(response.headers.value('X-WP-Total') ?? '0') ?? 0;
          final int totalPages = int.tryParse(response.headers.value('X-WP-TotalPages') ?? '0') ?? 0;
          return {'products': products, 'total_products': totalProducts, 'total_pages': totalPages};
        }
        throw InvalidDataException("Respuesta inesperada del servidor al buscar productos.");
      } catch (e) {
        if(e is ApiException) rethrow;
        throw ApiException("Error buscando productos por término '$query': $e");
      }
    }
  }

  Future<String> getProductById(String productId, {bool useCompute = false, bool includeParent = true}) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión para obtener producto.");
    final dio = await _getDioClient();

    final endpoint = connectionMode == 'plugin'
        ? 'wp-json/mypos/v1/producto/$productId'
        : 'wp-json/wc/v3/products/$productId';

    try {
      final response = await dio.get(endpoint);
      final data = _tryParseResponseData(response);
      if (data is Map<String, dynamic>) {
        return json.encode(data);
      }
      throw InvalidDataException("Respuesta inesperada para producto ID $productId.");
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw ProductNotFoundException(productId);
      _handleDioError(e, "obtener producto $productId", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// ✓ FASE 2 BATCH API: Obtiene múltiples productos en una sola petición
  /// Resuelve el problema N+1 al cargar pedidos con múltiples items
  Future<Map<String, dynamic>> getProductsBatch(List<int> ids, {bool lightweight = false}) async {
    if (ids.isEmpty) return {};
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión para obtener productos en lote.");

    final dio = await _getDioClient();
    final endpoint = 'wp-json/mypos/v1/productos/batch';

    try {
      final response = await dio.post(
        endpoint,
        data: {
          'ids': ids,
          'lightweight': lightweight,
        },
      );
      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic> && data['products'] is Map) {
        // El endpoint retorna: {products: {id: data}, count: N, requested: M, not_found: X}
        return data['products'] as Map<String, dynamic>;
      }
      throw InvalidDataException("Respuesta inesperada para el lote de productos.");
    } on DioException catch (e) {
      _handleDioError(e, "obtener productos en lote", throwException: true);
      throw StateError("Unreachable");
    }
  }

  Future<List<Map<String, dynamic>>> getAllVariationsForProduct(String productId, {bool onlyInStock = false}) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    final dio = await _getDioClient();

    if (connectionMode == 'plugin') {
      try {
        final response = await dio.get('wp-json/mypos/v1/producto/$productId/variaciones');
        final data = _tryParseResponseData(response);
        if (data is List) {
          var variations = data.whereType<Map<String, dynamic>>().toList();
          if (onlyInStock) {
            variations.retainWhere((v) => v['stock_status'] == 'instock');
          }
          return variations;
        }
        throw InvalidDataException("Respuesta inesperada del endpoint de variaciones del plugin.");
      } on DioException catch (e) {
        _handleDioError(e, "obtener variaciones (plugin) $productId", throwException: true);
        throw StateError("Unreachable");
      }
    } else {
      List<Map<String, dynamic>> allVariations = [];
      int currentPage = 1;
      while (true) {
        final response = await dio.get('wp-json/wc/v3/products/$productId/variations', queryParameters: {
          'per_page': 100,
          'page': currentPage++,
          if (onlyInStock) 'stock_status': 'instock'
        });
        final data = _tryParseResponseData(response) as List;
        allVariations.addAll(data.cast<Map<String, dynamic>>());
        if (data.length < 100) break;
      }
      return allVariations;
    }
  }

  Future<Map<String, dynamic>> activateManageStockForAllVariables() async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    if (connectionMode != 'plugin') throw ApiException("Esta función solo está soportada en modo plugin.");
    try {
      final dio = await _getDioClient();
      final response = await dio.post('wp-json/mypos/v1/activar-gestion-stock-variables', data: {'activate': true});
      final data = _tryParseResponseData(response);
      if(data is Map<String, dynamic>) return data;
      throw InvalidDataException("Respuesta inesperada del servidor.");
    } on DioException catch (e) {
      _handleDioError(e, "activar stock para variables", throwException: true);
      throw StateError("Unreachable");
    }
  }

  Future<void> updateMultipleProductsStock(List<Map<String, dynamic>> updates) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión para actualizar stock.");
    if (connectionMode != 'plugin') {
      throw ApiException("La actualización en lote solo está soportada en modo plugin.");
    }
    try {
      final dio = await _getDioClient();
      await dio.post('wp-json/mypos/v1/actualizar-stock', data: {'updates': updates});
    } on DioException catch (e) {
      _handleDioError(e, "actualizar stock en lote (plugin)", throwException: true);
    }
  }

  /// 🟢 PRIORIDAD 3: Obtener pedidos delta
  /// Retorna pedidos nuevos/modificados desde un timestamp
  Future<Map<String, dynamic>> getOrdersDelta({required int since}) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión para obtener pedidos delta.");
    }

    if (connectionMode != 'plugin') {
      throw ApiException("El endpoint delta solo está soportado en modo plugin.");
    }

    try {
      final dio = await _getDioClient();
      final response = await dio.get(
        'wp-json/mypos/v1/orders/delta',
        queryParameters: {'since': since},
      );

      final data = _tryParseResponseData(response);
      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada del endpoint delta.");
    } on DioException catch (e) {
      _handleDioError(e, "obtener pedidos delta", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// 🟢 NUEVO: Obtener productos delta (cambios de inventario externos)
  /// Retorna productos modificados fuera de la aplicación desde un timestamp
  Future<Map<String, dynamic>> getProductsDelta({
    required int since,
    int? priority,
    bool lightweight = false,
  }) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión para obtener productos delta.");
    }

    if (connectionMode != 'plugin') {
      throw ApiException("El endpoint delta solo está soportado en modo plugin.");
    }

    try {
      final dio = await _getDioClient();

      final queryParams = <String, dynamic>{'since': since, 'lightweight': lightweight};
      if (priority != null) {
        queryParams['priority'] = priority;
      }

      final response = await dio.get(
        'wp-json/mypos/v1/productos/delta',
        queryParameters: queryParams,
      );

      final data = _tryParseResponseData(response);
      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada del endpoint productos delta.");
    } on DioException catch (e) {
      _handleDioError(e, "obtener productos delta", throwException: true);
      throw StateError("Unreachable");
    }
  }

  Future<List<Map<String, dynamic>>> getCustomers({int perPage = 10, String orderBy = 'name', String order = 'asc'}) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    try {
      final dio = await _getDioClient();
      final response = await dio.get('wp-json/wc/v3/customers', queryParameters: {'per_page': perPage, 'orderby': orderBy, 'order': order});
      final data = _tryParseResponseData(response);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      throw InvalidDataException("Respuesta inesperada obteniendo clientes.");
    } catch(e) {
      if(e is ApiException) rethrow;
      throw ApiException("Error obteniendo clientes: $e");
    }
  }

  Future<List<Map<String, dynamic>>> searchCustomersAPI(String query) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    try {
      final dio = await _getDioClient();
      final response = await dio.get('wp-json/wc/v3/customers', queryParameters: {'search': query, 'per_page': 50});
      final data = _tryParseResponseData(response);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      throw InvalidDataException("Respuesta inesperada buscando clientes.");
    } catch(e) {
      if(e is ApiException) rethrow;
      throw ApiException("Error buscando clientes: $e");
    }
  }

  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> data) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    try {
      final dio = await _getDioClient();
      final Map<String, dynamic> payload = {
        'email': data['email'],
        'first_name': data['first_name'],
        'last_name': data['last_name'],
        'billing': {
          'first_name': data['first_name'],
          'last_name': data['last_name'],
          'email': data['email'],
          'phone': data['phone'],
        }
      };
      final response = await dio.post('wp-json/wc/v3/customers', data: payload);
      final responseData = _tryParseResponseData(response);
      if (responseData is Map<String, dynamic>) {
        return responseData;
      }
      throw InvalidDataException("Respuesta inválida al crear cliente.");
    } catch (e) {
      if(e is ApiException) rethrow;
      throw ApiException("Error creando cliente: ${e.toString()}");
    }
  }

  Future<Map<String, dynamic>> getOrderHistory({int page = 1, int perPage = 20, String? searchTerm, String? status}) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión para obtener el historial de pedidos.");
    final dio = await _getDioClient();
    try {
      final response = await dio.get('wp-json/mypos/v1/pedidos',
          queryParameters: {
            'page': page,
            'per_page': perPage,
            if (searchTerm != null && searchTerm.isNotEmpty) 'search': searchTerm,
            if (status != null && status.isNotEmpty && status != 'any')
              'status': status,
          });
      final data = _tryParseResponseData(response);
      if (data is List) {
        final orders = data
            .whereType<Map<String, dynamic>>()
            .map((item) => Order.fromJson(item))
            .toList();
        final int totalProducts =
            int.tryParse(response.headers.value('X-WP-Total') ?? '0') ?? 0;
        final int totalPages =
            int.tryParse(response.headers.value('X-WP-TotalPages') ?? '0') ?? 0;
        return {
          'orders': orders,
          'total_products': totalProducts,
          'total_pages': totalPages
        };
      }
      throw InvalidDataException(
          "Respuesta inesperada del plugin al buscar pedidos.");
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return {'orders': [], 'total_products': 0, 'total_pages': 0};
      }
      _handleDioError(e, "buscar pedidos vía plugin", throwException: true);
      throw StateError("Unreachable");
    }
  }

  Future<Order?> getOrderByIdAPI(String orderId) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión para obtener el pedido.");
    final dio = await _getDioClient();
    try {
      final response = await dio.get('wp-json/wc/v3/orders/$orderId');
      final data = _tryParseResponseData(response);
      if (data is Map<String, dynamic>) {
        return Order.fromJson(data);
      }
      throw InvalidDataException("Respuesta inesperada para el pedido ID $orderId.");
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw OrderNotFoundException(orderId);
      _handleDioError(e, "obtener pedido $orderId", throwException: true);
      throw StateError("Unreachable");
    }
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    if (orderId.startsWith('local_')) throw InvalidDataException("No se puede actualizar un pedido local en el servidor.");
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    try {
      final dio = await _getDioClient();
      await dio.put('wp-json/wc/v3/orders/$orderId', data: {'status': newStatus});
    } catch (e) {
      if(e is ApiException) rethrow;
      throw ApiException("Error actualizando estado del pedido: $e");
    }
  }

  Future<String?> createOrderAPI(Order order) async {
    if (order.items.isEmpty) throw InvalidDataException("El pedido no tiene productos.");
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    try {
      final dio = await _getDioClient();
      final response = await dio.post('wp-json/wc/v3/orders', data: order.toJson());
      final data = _tryParseResponseData(response);
      if (response.statusCode! >= 200 && response.statusCode! < 300 && data is Map<String, dynamic> && data['id'] != null) {
        return data['id'].toString();
      }
      throw InvalidDataException("Respuesta inválida al crear pedido.");
    } catch (e) {
      if(e is ApiException) rethrow;
      throw ApiException("Error creando pedido: $e");
    }
  }

  Future<Order> updateOrderAPI(Order order) async {
    if (order.items.isEmpty) throw InvalidDataException("El pedido no tiene productos para actualizar.");
    if (order.id == null || order.id!.isEmpty) throw InvalidDataException("El ID del pedido es requerido para actualizar.");
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    try {
      final dio = await _getDioClient();
      final response = await dio.put(
        'wp-json/wc/v3/orders/${order.id}',
        data: order.toJson(forUpdate: true),
      );
      final data = _tryParseResponseData(response);
      if (data is Map<String, dynamic>) {
        return Order.fromJson(data);
      }
      throw InvalidDataException("Respuesta inválida al actualizar pedido.");
    } catch (e) {
      if(e is ApiException) rethrow;
      throw ApiException("Error actualizando pedido: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getAllProductsWithStockManagement() async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    if (connectionMode != 'plugin') {
      throw ApiException("Esta función solo está disponible en modo plugin para un rendimiento óptimo.");
    }
    try {
      final dio = await _getDioClient();
      final response = await dio.get('wp-json/mypos/v1/productos-gestion-stock', queryParameters: {'per_page': 2000}); // Aumentado límite
      final data = _tryParseResponseData(response);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      throw InvalidDataException("Respuesta inesperada al obtener productos con gestión de stock.");
    } catch(e) {
      if(e is ApiException) rethrow;
      throw ApiException("Error obteniendo productos con gestión de stock: $e");
    }
  }

  Future<List<InventoryMovement>> getInventoryHistory() async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    try {
      final dio = await _getDioClient();
      final response = await dio.get('wp-json/mypos/v1/inventory-history');
      final data = _tryParseResponseData(response);
      if (data is List) {
        return data.map((json) => InventoryMovement.fromJson(json)).toList();
      }
      throw InvalidDataException("Respuesta inesperada obteniendo el historial de inventario.");
    } catch(e) {
      if(e is ApiException) rethrow;
      throw ApiException("Error obteniendo el historial de inventario: $e");
    }
  }

  Future<void> submitInventoryAdjustment(InventoryMovement movement) async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    if (connectionMode != 'plugin') throw ApiException("El ajuste de inventario solo está soportada en modo plugin.");
    try {
      final dio = await _getDioClient();
      await dio.post('wp-json/mypos/v1/inventory-adjustment', data: {'movement': movement.toJson()});
    } on DioException catch (e) {
      _handleDioError(e, "enviar ajuste de inventario", throwException: true);
    }
  }

  Future<List<Map<String, dynamic>>> getProductCategories() async {
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    final dio = await _getDioClient();
    try {
      final response = await dio.get('wp-json/wc/v3/products/categories', queryParameters: {'per_page': 100});
      final data = _tryParseResponseData(response);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      throw InvalidDataException("Respuesta inesperada al obtener categorías.");
    } on DioException catch (e) {
      _handleDioError(e, "obtener categorías de productos", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// ✓ FASE 2 STUB: Método stub para desactivar gestión de stock en variables
  Future<Map<String, dynamic>> deactivateManageStockForAllVariables() async {
    debugPrint("[WooCommerceService] deactivateManageStockForAllVariables - STUB not implemented");
    // TODO: Implementar endpoint personalizado en el plugin de WordPress si es necesario
    return {'message': 'Operación no implementada: deactivateManageStockForAllVariables'};
  }

  /// ✓ FASE 2 STUB: Método stub para activar gestión de stock en padres
  Future<Map<String, dynamic>> activateManageStockForAllParents() async {
    debugPrint("[WooCommerceService] activateManageStockForAllParents - STUB not implemented");
    // TODO: Implementar endpoint personalizado en el plugin de WordPress si es necesario
    return {'message': 'Operación no implementada: activateManageStockForAllParents'};
  }

  /// ✓ FASE 2 STUB: Método stub para desactivar gestión de stock en padres
  Future<Map<String, dynamic>> deactivateManageStockForAllParents() async {
    debugPrint("[WooCommerceService] deactivateManageStockForAllParents - STUB not implemented");
    // TODO: Implementar endpoint personalizado en el plugin de WordPress si es necesario
    return {'message': 'Operación no implementada: deactivateManageStockForAllParents'};
  }

  /// ✓ FASE 2 STUB: Método stub para obtener productos para sincronización de catálogo
  Future<List<Map<String, dynamic>>> fetchProductsForCatalogSync({
    required int page,
    required int perPage,
  }) async {
    debugPrint("[WooCommerceService] fetchProductsForCatalogSync page=$page perPage=$perPage - STUB using standard endpoint");
    // TODO: Si hay un endpoint optimizado en el plugin, usarlo aquí
    // Por ahora, usar el endpoint estándar de WooCommerce
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión.");
    final dio = await _getDioClient();
    try {
      final response = await dio.get(
        'wp-json/wc/v3/products',
        queryParameters: {
          'page': page,
          'per_page': perPage,
          'status': 'publish',
        },
      );
      final data = _tryParseResponseData(response);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } on DioException catch (e) {
      _handleDioError(e, "fetchProductsForCatalogSync", throwException: true);
      throw StateError("Unreachable");
    }
  }

  // ==================== ✅ NUEVO: DELTA SYNC METHODS ====================

  /// Registrar dispositivo para push notifications
  Future<void> registerDevice({
    required String fcmToken,
    required String deviceId,
  }) async {
    try {
      final dio = await _getDioClient();
      final response = await dio.post(
        '/mypos/v1/device/register',
        data: {
          'fcm_token': fcmToken,
          'device_id': deviceId,
        },
      );

      debugPrint("[WooCommerceService] Device registered: ${response.data}");
    } catch (e) {
      debugPrint("[WooCommerceService] Failed to register device: $e");
      rethrow;
    }
  }

  /// Obtener productos modificados desde un timestamp (Delta Sync)
  Future<Map<String, dynamic>> getDeltaProducts({
    required int since,
    int? priority,
    bool lightweight = false,
  }) async {
    try {
      final dio = await _getDioClient();

      final queryParams = {
        'since': since,
        'lightweight': lightweight,
      };

      if (priority != null) {
        queryParams['priority'] = priority;
      }

      final response = await dio.get(
        '/mypos/v1/productos/delta',
        queryParameters: queryParams,
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint("[WooCommerceService] Delta sync failed: $e");
      rethrow;
    }
  }

  // ==================== POLLING INTELIGENTE (Sin FCM) ====================

  /// Check pedidos nuevos (ultra ligero: ~50 bytes)
  Future<Map<String, dynamic>> checkNewOrders({
    required String deviceId,
    required int since,
  }) async {
    try {
      final dio = await _getDioClient();
      final response = await dio.get(
        '/mypos/v1/check-new-orders',
        queryParameters: {
          'device_id': deviceId,
          'since': since,
        },
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint("[WooCommerceService] Check new orders failed: $e");
      rethrow;
    }
  }

  /// Check stock crítico (ligero: ~200 bytes)
  Future<Map<String, dynamic>> checkCriticalStock({
    required int since,
  }) async {
    try {
      final dio = await _getDioClient();
      final response = await dio.get(
        '/mypos/v1/check-critical-stock',
        queryParameters: {
          'since': since,
        },
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint("[WooCommerceService] Check critical stock failed: $e");
      rethrow;
    }
  }

  /// Enviar heartbeat del dispositivo
  Future<void> sendDeviceHeartbeat({
    required String deviceId,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    try {
      final dio = await _getDioClient();
      await dio.post(
        '/mypos/v1/device/heartbeat',
        data: {
          'device_id': deviceId,
          'device_name': deviceName,
          'platform': platform,
          'app_version': appVersion,
        },
      );

      debugPrint("[WooCommerceService] Heartbeat sent successfully");
    } catch (e) {
      debugPrint("[WooCommerceService] Heartbeat failed: $e");
      // No rethrow - heartbeat failure is non-critical
    }
  }

  /// Obtener configuración de polling desde servidor
  Future<Map<String, dynamic>> getPollingConfig() async {
    try {
      final dio = await _getDioClient();
      final response = await dio.get('/mypos/v1/polling-config');

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint("[WooCommerceService] Get polling config failed: $e");
      rethrow;
    }
  }

  /// Marcar cambios como sincronizados
  Future<void> markChangesSynced(List<int> productIds) async {
    if (productIds.isEmpty) return;

    try {
      final dio = await _getDioClient();
      await dio.post(
        '/mypos/v1/mark-synced',
        data: {
          'product_ids': productIds,
        },
      );

      debugPrint("[WooCommerceService] ${productIds.length} changes marked as synced");
    } catch (e) {
      debugPrint("[WooCommerceService] Mark synced failed: $e");
      // No rethrow - marking as synced failure is non-critical
    }
  }

  // ==================== V3.1.0: LONG POLLING ====================

  /// Long Polling para notificaciones en tiempo real (30s wait)
  Future<Map<String, dynamic>> longPollChanges({
    required int lastId,
    int timeout = 25,
  }) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    try {
      final dio = await _getDioClient();

      // IMPORTANTE: Timeout debe ser mayor que el del servidor
      final response = await dio.get(
        'wp-json/mypos/v1/poll',
        queryParameters: {
          'last_id': lastId,
          'timeout': timeout,
        },
        options: Options(
          receiveTimeout: Duration(seconds: timeout + 10), // 35s
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada del long polling.");
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout) {
        // Timeout normal, no es error
        return {
          'status': 'timeout',
          'changes': [],
          'last_id': lastId,
        };
      }

      _handleDioError(e, "long polling", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// Confirmar recepción de cambios (ACK)
  Future<void> acknowledgeChanges(int lastId) async {
    if (!await _connectivityService.checkConnectivity()) return;

    try {
      final dio = await _getDioClient();

      await dio.post(
        'wp-json/mypos/v1/poll/ack',
        data: {'last_id': lastId},
      );

      debugPrint("[WooCommerceService] Changes acknowledged: $lastId");
    } catch (e) {
      debugPrint("[WooCommerceService] ⚠️ ACK failed: $e");
      // No lanzar error, es no-crítico
    }
  }

  // ==================== V3.1.0: DELTA SYNC ====================

  /// Obtener cambios delta desde timestamp
  Future<Map<String, dynamic>> getDeltaChanges({
    required int since,
    String type = 'compact',
    int limit = 100,
  }) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.get(
        'wp-json/mypos/v1/sync/delta',
        queryParameters: {
          'since': since,
          'type': type,
          'limit': limit,
        },
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada del delta sync.");
    } on DioException catch (e) {
      _handleDioError(e, "delta sync", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// Obtener productos en batch por IDs (v3.1.0)
  Future<List<Map<String, dynamic>>> getProductsBatchV310(List<int> ids) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    if (ids.isEmpty) return [];

    try {
      final dio = await _getDioClient();

      final response = await dio.post(
        'wp-json/mypos/v1/sync/products/batch',
        data: {'ids': ids},
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic> && data['products'] is List) {
        return (data['products'] as List).cast<Map<String, dynamic>>();
      }

      throw InvalidDataException("Respuesta inesperada del batch.");
    } on DioException catch (e) {
      _handleDioError(e, "products batch", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// Estadísticas de sincronización
  Future<Map<String, dynamic>> getDeltaStats() async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.get('wp-json/mypos/v1/sync/stats');

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada de stats.");
    } on DioException catch (e) {
      _handleDioError(e, "delta stats", throwException: true);
      throw StateError("Unreachable");
    }
  }

  // ==================== V3.1.0: BATCH OPERATIONS ====================

  /// Actualización masiva de stock (80% más rápido)
  Future<Map<String, dynamic>> batchUpdateStock(
    List<Map<String, dynamic>> items,
  ) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    if (items.isEmpty) {
      return {'success': true, 'updated': 0};
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.post(
        'wp-json/mypos/v1/batch/stock',
        data: {'items': items},
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada del batch stock.");
    } on DioException catch (e) {
      _handleDioError(e, "batch stock update", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// Actualización masiva de precios
  Future<Map<String, dynamic>> batchUpdatePrices(
    List<Map<String, dynamic>> items,
  ) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    if (items.isEmpty) {
      return {'success': true, 'updated': 0};
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.post(
        'wp-json/mypos/v1/batch/prices',
        data: {'items': items},
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada del batch prices.");
    } on DioException catch (e) {
      _handleDioError(e, "batch price update", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// Super Batch: Múltiples operaciones en una transacción
  Future<Map<String, dynamic>> batchOperations(
    List<Map<String, dynamic>> operations,
  ) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    if (operations.isEmpty) {
      return {'success': true, 'results': []};
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.post(
        'wp-json/mypos/v1/batch/v2',
        data: {'operations': operations},
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada del super batch.");
    } on DioException catch (e) {
      _handleDioError(e, "batch operations", throwException: true);
      throw StateError("Unreachable");
    }
  }

  // ==================== GESTIÓN DE CLIENTES ====================

  /// Obtener clientes recientes
  Future<List<Map<String, dynamic>>> getRecentCustomers({int limit = 10}) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.get(
        'wp-json/wc/v3/customers',
        queryParameters: {
          'per_page': limit,
          'orderby': 'date',
          'order': 'desc',
        },
      );

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }

      return [];
    } on DioException catch (e) {
      _handleDioError(e, "get recent customers");
      return [];
    }
  }

  /// Buscar clientes por término
  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    if (query.trim().isEmpty) {
      return getRecentCustomers();
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.get(
        'wp-json/wc/v3/customers',
        queryParameters: {
          'search': query.trim(),
          'per_page': 20,
        },
      );

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }

      return [];
    } on DioException catch (e) {
      _handleDioError(e, "search customers");
      return [];
    }
  }

  /// Crear nuevo cliente
  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> customerData) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.post(
        'wp-json/wc/v3/customers',
        data: customerData,
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
      }

      throw InvalidDataException("Respuesta inesperada al crear cliente.");
    } on DioException catch (e) {
      _handleDioError(e, "create customer", throwException: true);
      throw StateError("Unreachable");
    }
  }

  /// Obtener cliente por ID
  Future<Map<String, dynamic>?> getCustomerById(int customerId) async {
    if (!await _connectivityService.checkConnectivity()) {
      throw NetworkException("Sin conexión.");
    }

    try {
      final dio = await _getDioClient();

      final response = await dio.get(
        'wp-json/wc/v3/customers/$customerId',
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
      }

      return null;
    } on DioException catch (e) {
      _handleDioError(e, "get customer by id");
      return null;
    }
  }
}