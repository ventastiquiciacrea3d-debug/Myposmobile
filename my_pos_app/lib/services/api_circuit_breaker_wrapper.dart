// lib/services/api_circuit_breaker_wrapper.dart
import 'package:flutter/foundation.dart';
import 'circuit_breaker_service.dart';
import 'woocommerce_service.dart';

/// ✓ PROPUESTA 4: Wrapper para proteger llamadas API con Circuit Breaker
///
/// Este wrapper permite aplicar el patrón Circuit Breaker a cualquier
/// operación API sin modificar el código existente de forma masiva.
class ApiCircuitBreakerWrapper {
  final CircuitBreakerService _circuitBreaker;

  ApiCircuitBreakerWrapper(this._circuitBreaker);

  /// Ejecutar una llamada API protegida por el Circuit Breaker
  ///
  /// [operation] - La operación API a ejecutar
  /// [operationName] - Nombre descriptivo para logging
  /// [useCachedFallback] - Si true, retorna cached data cuando el circuit está OPEN
  /// [cachedDataProvider] - Función que retorna datos cacheados
  Future<T> executeApiCall<T>({
    required Future<T> Function() operation,
    required String operationName,
    bool useCachedFallback = true,
    Future<T> Function()? cachedDataProvider,
  }) async {
    try {
      return await _circuitBreaker.execute(
        operation,
        operationName: operationName,
        fallback: useCachedFallback && cachedDataProvider != null
            ? () async {
                debugPrint("[ApiWrapper] 🔄 Using cached fallback for $operationName");
                return await cachedDataProvider();
              }
            : null,
      );
    } on CircuitBreakerOpenException catch (e) {
      // El circuito está OPEN y no hay fallback disponible
      debugPrint("[ApiWrapper] 🔴 Circuit OPEN, no fallback: $operationName");
      throw NetworkException("Servicio temporalmente no disponible. ${e.message}");
    } catch (e) {
      // Error en la operación
      rethrow;
    }
  }

  /// Ejecutar múltiples operaciones API en paralelo con protección
  Future<List<T>> executeMultiple<T>({
    required List<Future<T> Function()> operations,
    required String operationName,
  }) async {
    final results = <T>[];

    for (int i = 0; i < operations.length; i++) {
      try {
        final result = await _circuitBreaker.execute(
          operations[i],
          operationName: "$operationName-$i",
        );
        results.add(result);
      } catch (e) {
        debugPrint("[ApiWrapper] ❌ Operation $i failed in batch: $e");
        // Continuar con las siguientes operaciones
      }
    }

    return results;
  }

  /// Verificar si el circuit breaker está disponible para peticiones
  bool get isAvailable => _circuitBreaker.state != CircuitBreakerState.open;

  /// Obtener estado actual del circuit breaker
  CircuitBreakerState get state => _circuitBreaker.state;

  /// Obtener métricas actuales
  CircuitBreakerMetrics get metrics => _circuitBreaker.metrics;
}

/// Helper extensions para tipos de operaciones comunes
extension CircuitBreakerApiExtensions on ApiCircuitBreakerWrapper {
  /// Ejecutar GET request con circuit breaker
  Future<T> get<T>({
    required Future<T> Function() apiCall,
    required String endpoint,
    Future<T> Function()? cached,
  }) async {
    return executeApiCall(
      operation: apiCall,
      operationName: "GET $endpoint",
      cachedDataProvider: cached,
    );
  }

  /// Ejecutar POST request con circuit breaker
  Future<T> post<T>({
    required Future<T> Function() apiCall,
    required String endpoint,
  }) async {
    return executeApiCall(
      operation: apiCall,
      operationName: "POST $endpoint",
      useCachedFallback: false, // No usar cache para operaciones de escritura
    );
  }

  /// Ejecutar PUT request con circuit breaker
  Future<T> put<T>({
    required Future<T> Function() apiCall,
    required String endpoint,
  }) async {
    return executeApiCall(
      operation: apiCall,
      operationName: "PUT $endpoint",
      useCachedFallback: false,
    );
  }

  /// Ejecutar DELETE request con circuit breaker
  Future<T> delete<T>({
    required Future<T> Function() apiCall,
    required String endpoint,
  }) async {
    return executeApiCall(
      operation: apiCall,
      operationName: "DELETE $endpoint",
      useCachedFallback: false,
    );
  }
}
