// lib/services/circuit_breaker_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

/// ✓ PROPUESTA 4: Circuit Breaker Service - Protección contra fallos en cascada
///
/// Implementa el patrón Circuit Breaker para proteger la app de:
/// 1. ✅ Llamadas repetidas a servicios que están fallando
/// 2. ✅ Cascada de fallos en toda la aplicación
/// 3. ✅ Timeout acumulativo por reintentos excesivos
/// 4. ✅ Sobrecarga del servidor durante recuperación
///
/// Estados:
/// - CLOSED: Funcionamiento normal, todas las peticiones pasan
/// - OPEN: Servicio fallando, peticiones bloqueadas inmediatamente
/// - HALF_OPEN: Estado de prueba, permite algunas peticiones para verificar recuperación
enum CircuitBreakerState {
  closed,   // Normal operation
  open,     // Failing, blocking requests
  halfOpen, // Testing if service recovered
}

/// Configuración del Circuit Breaker
class CircuitBreakerConfig {
  /// Número de fallos consecutivos antes de abrir el circuito
  final int failureThreshold;

  /// Tiempo que el circuito permanece OPEN antes de intentar HALF_OPEN
  final Duration resetTimeout;

  /// Número de peticiones exitosas en HALF_OPEN para cerrar el circuito
  final int successThreshold;

  /// Timeout para considerar una petición como fallida
  final Duration requestTimeout;

  /// Ventana de tiempo para contar fallos
  final Duration failureWindow;

  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 30),
    this.successThreshold = 2,
    this.requestTimeout = const Duration(seconds: 15),
    this.failureWindow = const Duration(minutes: 1),
  });
}

/// Evento de cambio de estado del Circuit Breaker
class CircuitBreakerEvent {
  final CircuitBreakerState previousState;
  final CircuitBreakerState newState;
  final String reason;
  final DateTime timestamp;

  CircuitBreakerEvent({
    required this.previousState,
    required this.newState,
    required this.reason,
  }) : timestamp = DateTime.now();

  @override
  String toString() => '[CircuitBreaker] $previousState → $newState: $reason';
}

/// Métricas del Circuit Breaker
class CircuitBreakerMetrics {
  int totalRequests = 0;
  int successfulRequests = 0;
  int failedRequests = 0;
  int rejectedRequests = 0;
  DateTime? lastFailureTime;
  DateTime? lastSuccessTime;
  Duration? averageResponseTime;

  double get successRate => totalRequests > 0
      ? successfulRequests / totalRequests
      : 0.0;

  double get failureRate => totalRequests > 0
      ? failedRequests / totalRequests
      : 0.0;

  Map<String, dynamic> toJson() => {
    'totalRequests': totalRequests,
    'successfulRequests': successfulRequests,
    'failedRequests': failedRequests,
    'rejectedRequests': rejectedRequests,
    'successRate': successRate,
    'failureRate': failureRate,
    'lastFailureTime': lastFailureTime?.toIso8601String(),
    'lastSuccessTime': lastSuccessTime?.toIso8601String(),
    'averageResponseTime': averageResponseTime?.inMilliseconds,
  };
}

/// Circuit Breaker Service
class CircuitBreakerService extends ChangeNotifier {
  final CircuitBreakerConfig config;

  CircuitBreakerState _state = CircuitBreakerState.closed;
  CircuitBreakerState get state => _state;

  final CircuitBreakerMetrics _metrics = CircuitBreakerMetrics();
  CircuitBreakerMetrics get metrics => _metrics;

  int _consecutiveFailures = 0;
  int _consecutiveSuccesses = 0;
  DateTime? _openedAt;
  Timer? _resetTimer;

  final List<DateTime> _recentFailures = [];
  final List<Duration> _recentResponseTimes = [];

  // Stream de eventos para monitoreo
  final StreamController<CircuitBreakerEvent> _eventController =
      StreamController<CircuitBreakerEvent>.broadcast();
  Stream<CircuitBreakerEvent> get onStateChange => _eventController.stream;

  CircuitBreakerService({
    this.config = const CircuitBreakerConfig(),
  }) {
    debugPrint("[CircuitBreakerService] ✓ Initialized with config: "
        "failureThreshold=${config.failureThreshold}, "
        "resetTimeout=${config.resetTimeout.inSeconds}s");
  }

  /// Ejecutar una operación protegida por el Circuit Breaker
  Future<T> execute<T>(
    Future<T> Function() operation, {
    Future<T> Function()? fallback,
    String operationName = 'unknown',
  }) async {
    // Si el circuito está OPEN, rechazar inmediatamente
    if (_state == CircuitBreakerState.open) {
      _metrics.rejectedRequests++;
      debugPrint("[CircuitBreaker] 🔴 Request REJECTED ($operationName) - Circuit is OPEN");

      if (fallback != null) {
        debugPrint("[CircuitBreaker] 🔄 Executing fallback for $operationName");
        return await fallback();
      }

      throw CircuitBreakerOpenException(
        "Circuit breaker is OPEN. Service unavailable. "
        "Next retry in ${_timeUntilHalfOpen()}",
      );
    }

    _metrics.totalRequests++;
    final startTime = DateTime.now();

    try {
      // Ejecutar operación con timeout
      final result = await operation().timeout(config.requestTimeout);

      // Registrar éxito
      final duration = DateTime.now().difference(startTime);
      _recordSuccess(duration);

      debugPrint("[CircuitBreaker] ✅ Request SUCCESS ($operationName) - ${duration.inMilliseconds}ms");

      return result;
    } on TimeoutException catch (e) {
      debugPrint("[CircuitBreaker] ⏱️ Request TIMEOUT ($operationName)");
      _recordFailure();
      rethrow;
    } catch (e) {
      debugPrint("[CircuitBreaker] ❌ Request FAILED ($operationName): ${e.runtimeType}");
      _recordFailure();
      rethrow;
    }
  }

  /// Registrar un éxito
  void _recordSuccess(Duration responseTime) {
    _metrics.successfulRequests++;
    _metrics.lastSuccessTime = DateTime.now();

    // Actualizar tiempo de respuesta promedio
    _recentResponseTimes.add(responseTime);
    if (_recentResponseTimes.length > 10) {
      _recentResponseTimes.removeAt(0);
    }
    _metrics.averageResponseTime = Duration(
      milliseconds: _recentResponseTimes
          .map((d) => d.inMilliseconds)
          .reduce((a, b) => a + b) ~/ _recentResponseTimes.length,
    );

    _consecutiveFailures = 0;
    _consecutiveSuccesses++;

    // Si estamos en HALF_OPEN y alcanzamos el umbral de éxito, cerrar el circuito
    if (_state == CircuitBreakerState.halfOpen &&
        _consecutiveSuccesses >= config.successThreshold) {
      _transitionTo(
        CircuitBreakerState.closed,
        "Success threshold reached in HALF_OPEN state",
      );
    }

    notifyListeners();
  }

  /// Registrar un fallo
  void _recordFailure() {
    _metrics.failedRequests++;
    _metrics.lastFailureTime = DateTime.now();

    _consecutiveSuccesses = 0;
    _consecutiveFailures++;

    // Agregar a lista de fallos recientes
    _recentFailures.add(DateTime.now());

    // Limpiar fallos antiguos fuera de la ventana de tiempo
    _cleanupOldFailures();

    // Verificar si debemos abrir el circuito
    if (_state == CircuitBreakerState.closed &&
        _consecutiveFailures >= config.failureThreshold) {
      _transitionTo(
        CircuitBreakerState.open,
        "Failure threshold reached ($_consecutiveFailures failures)",
      );
      _scheduleHalfOpenTransition();
    } else if (_state == CircuitBreakerState.halfOpen) {
      // Si falla en HALF_OPEN, volver a OPEN
      _transitionTo(
        CircuitBreakerState.open,
        "Request failed in HALF_OPEN state",
      );
      _scheduleHalfOpenTransition();
    }

    notifyListeners();
  }

  /// Limpiar fallos antiguos fuera de la ventana de tiempo
  void _cleanupOldFailures() {
    final now = DateTime.now();
    _recentFailures.removeWhere(
      (failureTime) => now.difference(failureTime) > config.failureWindow,
    );
  }

  /// Transición entre estados
  void _transitionTo(CircuitBreakerState newState, String reason) {
    final previousState = _state;
    _state = newState;

    final event = CircuitBreakerEvent(
      previousState: previousState,
      newState: newState,
      reason: reason,
    );

    debugPrint(event.toString());
    _eventController.add(event);

    if (newState == CircuitBreakerState.open) {
      _openedAt = DateTime.now();
    } else if (newState == CircuitBreakerState.closed) {
      _openedAt = null;
      _consecutiveFailures = 0;
      _consecutiveSuccesses = 0;
    }

    notifyListeners();
  }

  /// Programar transición a HALF_OPEN después del reset timeout
  void _scheduleHalfOpenTransition() {
    _resetTimer?.cancel();
    _resetTimer = Timer(config.resetTimeout, () {
      if (_state == CircuitBreakerState.open) {
        _transitionTo(
          CircuitBreakerState.halfOpen,
          "Reset timeout elapsed, attempting recovery",
        );
      }
    });
  }

  /// Tiempo restante hasta el próximo intento (HALF_OPEN)
  Duration _timeUntilHalfOpen() {
    if (_state != CircuitBreakerState.open || _openedAt == null) {
      return Duration.zero;
    }

    final elapsed = DateTime.now().difference(_openedAt!);
    final remaining = config.resetTimeout - elapsed;

    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Forzar el estado del circuito (para testing o manual override)
  void forceState(CircuitBreakerState newState, {String reason = "Manual override"}) {
    debugPrint("[CircuitBreaker] 🔧 FORCE STATE: $_state → $newState");
    _transitionTo(newState, reason);
  }

  /// Resetear métricas
  void resetMetrics() {
    _metrics.totalRequests = 0;
    _metrics.successfulRequests = 0;
    _metrics.failedRequests = 0;
    _metrics.rejectedRequests = 0;
    _metrics.lastFailureTime = null;
    _metrics.lastSuccessTime = null;
    _metrics.averageResponseTime = null;

    _consecutiveFailures = 0;
    _consecutiveSuccesses = 0;
    _recentFailures.clear();
    _recentResponseTimes.clear();

    notifyListeners();
    debugPrint("[CircuitBreaker] 🔄 Metrics reset");
  }

  /// Obtener estado actual como JSON
  Map<String, dynamic> getStatus() {
    return {
      'state': _state.name,
      'consecutiveFailures': _consecutiveFailures,
      'consecutiveSuccesses': _consecutiveSuccesses,
      'timeUntilHalfOpen': _timeUntilHalfOpen().inSeconds,
      'recentFailuresCount': _recentFailures.length,
      'metrics': _metrics.toJson(),
      'config': {
        'failureThreshold': config.failureThreshold,
        'resetTimeout': config.resetTimeout.inSeconds,
        'successThreshold': config.successThreshold,
        'requestTimeout': config.requestTimeout.inSeconds,
      },
    };
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _eventController.close();
    super.dispose();
    debugPrint("[CircuitBreakerService] Disposed");
  }
}

/// Excepción cuando el Circuit Breaker está abierto
class CircuitBreakerOpenException implements Exception {
  final String message;
  CircuitBreakerOpenException(this.message);

  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}
