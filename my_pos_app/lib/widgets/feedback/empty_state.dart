// lib/widgets/feedback/empty_state.dart
import 'package:flutter/material.dart';

/// ✓ PROPUESTA 7: Empty State Widget con ilustraciones y acciones
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icono con animación sutil
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: (iconColor ?? Theme.of(context).primaryColor).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 64,
                  color: iconColor ?? Theme.of(context).primaryColor,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Título
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // Mensaje
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            // Botón de acción (opcional)
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 20),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Factory constructors para casos comunes

  factory EmptyState.noOrders({VoidCallback? onCreateOrder}) {
    return EmptyState(
      icon: Icons.receipt_long_outlined,
      title: "No hay pedidos",
      message: "Aún no tienes ningún pedido registrado.\nComienza a crear tu primer pedido.",
      actionLabel: "Crear Pedido",
      onAction: onCreateOrder,
      iconColor: const Color(0xFF42A5F5),
    );
  }

  factory EmptyState.noProducts({VoidCallback? onAddProduct}) {
    return EmptyState(
      icon: Icons.inventory_2_outlined,
      title: "No hay productos",
      message: "No se encontraron productos en el inventario.\nIntenta sincronizar con el servidor.",
      actionLabel: "Sincronizar",
      onAction: onAddProduct,
      iconColor: const Color(0xFFFFA726),
    );
  }

  factory EmptyState.noMovements() {
    return const EmptyState(
      icon: Icons.swap_horiz,
      title: "Sin movimientos",
      message: "No hay movimientos de inventario registrados aún.",
      iconColor: Color(0xFF66BB6A),
    );
  }

  factory EmptyState.noLabels() {
    return const EmptyState(
      icon: Icons.label_outline,
      title: "Cola de impresión vacía",
      message: "No hay etiquetas pendientes de imprimir.",
      iconColor: Color(0xFF9575CD),
    );
  }

  factory EmptyState.searchNoResults(String searchTerm) {
    return EmptyState(
      icon: Icons.search_off,
      title: "Sin resultados",
      message: "No se encontraron resultados para \"$searchTerm\".\nIntenta con otros términos de búsqueda.",
      iconColor: const Color(0xFF78909C),
    );
  }

  factory EmptyState.networkError({VoidCallback? onRetry}) {
    return EmptyState(
      icon: Icons.cloud_off,
      title: "Error de conexión",
      message: "No se pudo conectar al servidor.\nVerifica tu conexión a internet e intenta de nuevo.",
      actionLabel: "Reintentar",
      onAction: onRetry,
      iconColor: const Color(0xFFE57373),
    );
  }
}
