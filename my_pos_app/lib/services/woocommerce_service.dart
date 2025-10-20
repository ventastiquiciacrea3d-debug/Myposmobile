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
import '../locator.dart';
import '../config/constants.dart';

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

      _dio = Dio(BaseOptions(
        baseUrl: sanitizedUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 120),
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', 'User-Agent': 'MyPOSMobileBarcode/3.1.0', },
        responseType: ResponseType.plain,
      ));

      _dio.interceptors.clear();
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

    try {
      final tempDio = Dio(BaseOptions(baseUrl: _dio.options.baseUrl, responseType: ResponseType.plain));
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

    try {
      final tempDio = Dio(BaseOptions(baseUrl: _dio.options.baseUrl, responseType: ResponseType.plain));
      final response = await tempDio.post(
          'wp-json/mypos/v1/register-device',
          data: {
            'api_key': masterApiKey,
            'device_uuid': deviceUuid,
            'device_name': deviceName,
          }
      );

      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic> && data['access_token'] != null && data['refresh_token'] != null) {
        await _storageService.saveAccessToken(data['access_token']);
        await _storageService.saveRefreshToken(data['refresh_token']);
        await initializeDioClient();
      } else {
        throw AuthenticationException("La respuesta de registro no contiene tokens válidos.");
      }
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
          if(throwException) throw parseError;
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

  Future<Map<String, dynamic>> getProductsBatch(List<int> ids) async {
    if (ids.isEmpty) return {};
    if (!await _connectivityService.checkConnectivity()) throw NetworkException("Sin conexión para obtener productos en lote.");

    final dio = await _getDioClient();
    final endpoint = 'wp-json/mypos/v1/products/batch';

    try {
      final response = await dio.post(endpoint, data: {'ids': ids});
      final data = _tryParseResponseData(response);

      if (data is Map<String, dynamic>) {
        return data;
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
}