// lib/widgets/circuit_breaker_status.dart
import 'package:flutter/material.dart';
import '../services/circuit_breaker_service.dart';

/// ✓ PROPUESTA 4: Widget para mostrar el estado del Circuit Breaker
class CircuitBreakerStatusIndicator extends StatelessWidget {
  final CircuitBreakerService circuitBreaker;
  final bool compact;

  const CircuitBreakerStatusIndicator({
    super.key,
    required this.circuitBreaker,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: circuitBreaker,
      builder: (context, _) {
        final state = circuitBreaker.state;
        final metrics = circuitBreaker.metrics;

        if (compact) {
          return _buildCompactIndicator(state, metrics);
        } else {
          return _buildDetailedCard(state, metrics);
        }
      },
    );
  }

  /// Indicador compacto para AppBar
  Widget _buildCompactIndicator(
    CircuitBreakerState state,
    CircuitBreakerMetrics metrics,
  ) {
    Color color;
    IconData icon;
    String tooltip;

    switch (state) {
      case CircuitBreakerState.closed:
        color = const Color(0xFF4CAF50); // Verde
        icon = Icons.check_circle;
        tooltip = "API funcionando normalmente";
        break;
      case CircuitBreakerState.halfOpen:
        color = const Color(0xFFFFA726); // Naranja
        icon = Icons.warning;
        tooltip = "API en recuperación";
        break;
      case CircuitBreakerState.open:
        color = const Color(0xFFE53935); // Rojo
        icon = Icons.error;
        tooltip = "API temporalmente bloqueada";
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              state.name.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Card detallado para pantalla de settings
  Widget _buildDetailedCard(
    CircuitBreakerState state,
    CircuitBreakerMetrics metrics,
  ) {
    Color stateColor;
    IconData stateIcon;
    String stateDescription;

    switch (state) {
      case CircuitBreakerState.closed:
        stateColor = const Color(0xFF4CAF50);
        stateIcon = Icons.check_circle_outline;
        stateDescription = "La API está funcionando correctamente. "
            "Todas las peticiones se procesan normalmente.";
        break;
      case CircuitBreakerState.halfOpen:
        stateColor = const Color(0xFFFFA726);
        stateIcon = Icons.sync;
        stateDescription = "La API está en proceso de recuperación. "
            "Se están probando algunas peticiones.";
        break;
      case CircuitBreakerState.open:
        stateColor = const Color(0xFFE53935);
        stateIcon = Icons.block;
        stateDescription = "La API está temporalmente bloqueada debido a "
            "múltiples fallos. Las peticiones se rechazarán hasta la recuperación.";
        break;
    }

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: stateColor.withOpacity(0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado actual
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: stateColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(stateIcon, color: stateColor, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Estado: ${state.name.toUpperCase()}",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: stateColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stateDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Métricas
            Text(
              "Métricas",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),

            _buildMetricRow(
              "Total de Peticiones",
              "${metrics.totalRequests}",
              Icons.analytics,
            ),
            _buildMetricRow(
              "Tasa de Éxito",
              "${(metrics.successRate * 100).toStringAsFixed(1)}%",
              Icons.check_circle_outline,
              valueColor: const Color(0xFF4CAF50),
            ),
            _buildMetricRow(
              "Tasa de Fallos",
              "${(metrics.failureRate * 100).toStringAsFixed(1)}%",
              Icons.error_outline,
              valueColor: const Color(0xFFE53935),
            ),
            _buildMetricRow(
              "Peticiones Rechazadas",
              "${metrics.rejectedRequests}",
              Icons.block,
              valueColor: const Color(0xFFFFA726),
            ),

            if (metrics.averageResponseTime != null)
              _buildMetricRow(
                "Tiempo Promedio",
                "${metrics.averageResponseTime!.inMilliseconds}ms",
                Icons.timer_outlined,
              ),

            // Botón de reset (solo para debugging/testing)
            if (state == CircuitBreakerState.open) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    circuitBreaker.forceState(
                      CircuitBreakerState.closed,
                      reason: "Manual reset by user",
                    );
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text("Forzar Reset (Solo Testing)"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: stateColor,
                    side: BorderSide(color: stateColor),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge simple para mostrar en el AppBar
class CircuitBreakerBadge extends StatelessWidget {
  final CircuitBreakerService circuitBreaker;

  const CircuitBreakerBadge({
    super.key,
    required this.circuitBreaker,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: circuitBreaker,
      builder: (context, _) {
        if (circuitBreaker.state == CircuitBreakerState.closed) {
          // No mostrar nada si todo está bien
          return const SizedBox.shrink();
        }

        Color color = circuitBreaker.state == CircuitBreakerState.halfOpen
            ? const Color(0xFFFFA726)
            : const Color(0xFFE53935);

        return GestureDetector(
          onTap: () {
            _showCircuitBreakerDialog(context);
          },
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  "API",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCircuitBreakerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            const Text("Estado de la API"),
          ],
        ),
        content: CircuitBreakerStatusIndicator(
          circuitBreaker: circuitBreaker,
          compact: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }
}
