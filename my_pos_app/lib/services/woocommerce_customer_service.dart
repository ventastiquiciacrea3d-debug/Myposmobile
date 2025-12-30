// lib/services/woocommerce_customer_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/customer_model.dart';

/// Servicio para manejar clientes de WooCommerce
class WooCommerceCustomerService {
  final String baseUrl;
  final String consumerKey;
  final String consumerSecret;

  // Cache de clientes (5 minutos)
  static const Duration _cacheDuration = Duration(minutes: 5);
  DateTime? _lastFetchTime;
  List<CustomerModel>? _cachedCustomers;

  WooCommerceCustomerService({
    required this.baseUrl,
    required this.consumerKey,
    required this.consumerSecret,
  });

  /// Headers comunes para requests
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
      };

  /// Construir URL con autenticación
  String _buildUrl(String endpoint, [Map<String, String>? queryParams]) {
    final uri = Uri.parse('$baseUrl/wp-json/wc/v3/$endpoint');

    if (queryParams != null) {
      return uri.replace(queryParameters: queryParams).toString();
    }

    return uri.toString();
  }

  /// Obtener todos los clientes (con cache)
  Future<List<CustomerModel>> getAllCustomers({
    bool forceRefresh = false,
    int perPage = 100,
  }) async {
    // Verificar cache
    if (!forceRefresh &&
        _cachedCustomers != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return _cachedCustomers!;
    }

    final customers = <CustomerModel>[];
    int page = 1;
    bool hasMore = true;

    while (hasMore) {
      final url = _buildUrl('customers', {
        'per_page': perPage.toString(),
        'page': page.toString(),
      });

      final response = await http.get(Uri.parse(url), headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        if (data.isEmpty) {
          hasMore = false;
        } else {
          customers.addAll(
            data.map((json) => CustomerModel.fromWooCommerce(json)),
          );
          page++;
        }
      } else {
        throw Exception('Error al obtener clientes: ${response.statusCode}');
      }
    }

    // Actualizar cache
    _cachedCustomers = customers;
    _lastFetchTime = DateTime.now();

    return customers;
  }

  /// Buscar clientes en WooCommerce
  Future<List<CustomerModel>> searchCustomers(String query) async {
    final url = _buildUrl('customers', {
      'search': query,
      'per_page': '50',
    });

    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => CustomerModel.fromWooCommerce(json)).toList();
    } else {
      throw Exception('Error al buscar clientes: ${response.statusCode}');
    }
  }

  /// Obtener cliente por ID
  Future<CustomerModel?> getCustomerById(int id) async {
    final url = _buildUrl('customers/$id');

    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return CustomerModel.fromWooCommerce(data);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Error al obtener cliente: ${response.statusCode}');
    }
  }

  /// Crear nuevo cliente en WooCommerce
  Future<CustomerModel> createCustomer(CustomerModel customer) async {
    final url = _buildUrl('customers');

    final response = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: json.encode(customer.toWooCommerceJson()),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      _invalidateCache(); // Invalidar cache
      return CustomerModel.fromWooCommerce(data);
    } else {
      throw Exception('Error al crear cliente: ${response.body}');
    }
  }

  /// Actualizar cliente en WooCommerce
  Future<CustomerModel> updateCustomer(CustomerModel customer) async {
    if (customer.id == null) {
      throw Exception('El cliente debe tener un ID para actualizar');
    }

    final url = _buildUrl('customers/${customer.id}');

    final response = await http.put(
      Uri.parse(url),
      headers: _headers,
      body: json.encode(customer.toWooCommerceJson()),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _invalidateCache(); // Invalidar cache
      return CustomerModel.fromWooCommerce(data);
    } else {
      throw Exception('Error al actualizar cliente: ${response.body}');
    }
  }

  /// Eliminar cliente de WooCommerce
  Future<bool> deleteCustomer(int id, {bool force = false}) async {
    final url = _buildUrl('customers/$id', {
      'force': force.toString(),
    });

    final response = await http.delete(Uri.parse(url), headers: _headers);

    if (response.statusCode == 200) {
      _invalidateCache(); // Invalidar cache
      return true;
    } else {
      throw Exception('Error al eliminar cliente: ${response.statusCode}');
    }
  }

  /// Invalidar cache
  void _invalidateCache() {
    _cachedCustomers = null;
    _lastFetchTime = null;
  }

  /// Limpiar cache manualmente
  void clearCache() {
    _invalidateCache();
  }
}
