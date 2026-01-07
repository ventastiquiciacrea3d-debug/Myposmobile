// lib/widgets/order_notification_listener.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/order_notification_notifier.dart';
import '../config/routes.dart';

/// Widget que escucha las notificaciones de pedidos y las muestra
/// Este widget debe estar en un nivel alto de la jerarquía de widgets
class OrderNotificationListener extends ConsumerStatefulWidget {
  final Widget child;

  const OrderNotificationListener({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  ConsumerState<OrderNotificationListener> createState() => _OrderNotificationListenerState();
}

class _OrderNotificationListenerState extends ConsumerState<OrderNotificationListener> {
  int _lastNotificationCount = 0;

  @override
  Widget build(BuildContext context) {
    final notificationState = ref.watch(orderNotificationNotifierProvider);

    // Detectar nuevas notificaciones
    if (notificationState.notifications.isNotEmpty &&
        notificationState.notifications.length > _lastNotificationCount) {
      // Hay una nueva notificación, mostrarla
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNewOrderNotification(
          context,
          notificationState.notifications.first,
        );
      });
    }

    _lastNotificationCount = notificationState.notifications.length;

    return widget.child;
  }

  void _showNewOrderNotification(BuildContext context, Map<String, dynamic> notification) {
    final orderNumber = notification['order_number'] ?? 'N/A';
    final customerName = notification['customer_name'] ?? 'Cliente desconocido';
    final total = notification['order_total'] ?? 0.0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2E7D32), // Verde oscuro
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                const Text(
                  '¡Nuevo Pedido!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pedido #$orderNumber',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Cliente: $customerName',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            Text(
              'Total: ₡${total.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'VER',
          textColor: Colors.white,
          onPressed: () {
            // Navegar a la pantalla de pedido actual
            Routes.navigateTo(context, Routes.order);
          },
        ),
      ),
    );

    // También mostrar un diálogo si la app está en primer plano
    _showNewOrderDialog(context, notification);
  }

  void _showNewOrderDialog(BuildContext context, Map<String, dynamic> notification) {
    final orderNumber = notification['order_number'] ?? 'N/A';
    final customerName = notification['customer_name'] ?? 'Cliente desconocido';
    final total = notification['order_total'] ?? 0.0;
    final items = notification['items'] as List? ?? [];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.shopping_cart,
                color: Color(0xFF2E7D32),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '¡Nuevo Pedido!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Pedido', '#$orderNumber'),
              const SizedBox(height: 8),
              _buildInfoRow('Cliente', customerName),
              const SizedBox(height: 8),
              _buildInfoRow('Total', '₡${total.toStringAsFixed(0)}'),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Productos:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final name = item['product_name'] ?? 'Producto';
                  final quantity = item['quantity'] ?? 1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $name x$quantity',
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  );
                }).toList(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CERRAR'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Routes.navigateTo(context, Routes.order);
            },
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text('VER PEDIDO'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: Colors.black54,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
