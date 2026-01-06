// lib/screens/order_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../models/order.dart' show Order, OrderItem, StringExtension;
import '../models/product.dart' as app_product;
import '../models/ui_state.dart';
import '../providers/customer_notifier.dart' hide Customer; // ✅ FASE 3: Evitar conflicto con models/customer.dart
import '../providers/order_notifier.dart';
import '../providers/order_history_notifier.dart';
import '../providers/app_state_notifier.dart';

import '../widgets/app_header.dart';
import '../widgets/dial_floating_action_button.dart';
import '../widgets/custom_fab_location.dart';
import '../config/constants.dart';
import '../config/routes.dart';
import '../utils/pdf_generator.dart';

import '../widgets/order/current_order_item_card.dart';
import '../widgets/order/history_order_item_card.dart';
import '../widgets/customer_selection_dialog.dart'; // ✅ Customer selection dialog
import '../widgets/share_quote_dialog.dart'; // ✅ QUOTE: Share quote dialog
import '../screens/draft_orders_screen.dart'; // ✅ FASE 3: Draft orders
import '../models/customer.dart'; // ✅ CLIENTES: Customer model

import '../services/woocommerce_service.dart';
import '../services/storage_service.dart'; // ✅ FASE 3: Para draft orders
import '../services/quote_share_service.dart'; // ✅ QUOTE: Quote share service
import '../locator.dart'; // ✅ FASE 3: Para getIt

class ModalScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final String? confirmText;

  const ModalScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onCancel,
    this.onConfirm,
    this.confirmText,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
          ),
          Flexible(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: child
              )
          ),
          if (onCancel != null || onConfirm != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onCancel != null)
                    TextButton(onPressed: onCancel, child: const Text("CANCELAR")),
                  if (onConfirm != null && confirmText != null) ...[
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: onConfirm, child: Text(confirmText!)),
                  ]
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class DisplayVariantSelection {
  final String id;
  final String name;
  final int stock;
  final double price;
  final bool isAvailable;
  final app_product.Product productInstance;

  DisplayVariantSelection({
    required this.id,
    required this.name,
    required this.stock,
    required this.price,
    required this.isAvailable,
    required this.productInstance,
  });
}


class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key});
  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> with TickerProviderStateMixin {
  final currencyFormat = NumberFormat.currency(locale: 'es_CR', symbol: '₡');
  final dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm', 'es_CR');
  final shortDateFormat = DateFormat('dd/MM/yyyy', 'es_CR');
  late TabController _tabController;
  final ScrollController _historyScrollController = ScrollController();
  final TextEditingController _searchHistoryController = TextEditingController();
  Timer? _searchDebounce;
  final Map<String, SlidableController> _slidableControllers = {};

  String _selectedStatusFilter = 'any';
  String? _expandedOrderItemIdActual;
  String? _swipedOrderIdHistory;
  String? _expandedOrderIdHistory;
  int _currentBottomNavIndex = 1;

  static final List<Map<String, dynamic>> _statusOptionsListForCurrentOrder = [
    {"name": "Pendiente", "color": Colors.amber.shade700, "value": "pending"},
    {"name": "En espera", "color": Colors.orange.shade600, "value": "on-hold"},
    {"name": "Completado", "color": Colors.green.shade600, "value": "completed"},
  ];

  static final List<Map<String, dynamic>> _allPossibleStatusDisplayInfo = [
    {"name": "Pendiente", "color": Colors.amber.shade700, "value": "pending"},
    {"name": "En proceso", "color": Colors.blue.shade600, "value": "processing"},
    {"name": "En espera", "color": Colors.orange.shade600, "value": "on-hold"},
    {"name": "Completado", "color": Colors.green.shade600, "value": "completed"},
    {"name": "Cancelado", "color": Colors.red.shade600, "value": "cancelled"},
    {"name": "Cancelado", "color": Colors.red.shade600, "value": "canceled"},
    {"name": "Reembolsado", "color": Colors.purple.shade600, "value": "refunded"},
    {"name": "Fallido", "color": Colors.red.shade800, "value": "failed"},
    {"name": "Papelera", "color": Colors.grey.shade500, "value": "trash"},
  ];

  static final Map<String, String> _orderStatusesForFilterUI = {
    'any': 'Cualquiera (No Papelera)',
    'pending': 'Pendiente',
    'on-hold': 'En espera',
    'processing': 'En proceso',
    'completed': 'Completado',
    'cancelled': 'Cancelado',
    'refunded': 'Reembolsado',
    'failed': 'Fallido',
    'trash': 'Papelera',
  };

  Color _getStatusColor(String statusKey) {
    final statusOption = _allPossibleStatusDisplayInfo.firstWhere(
            (s) => s['value'] == statusKey.toLowerCase(),
        orElse: () => {"color": Colors.grey.shade600, "name": statusKey.capitalizeFirst()});
    return statusOption['color'] as Color;
  }

  IconData _getIconForStatusValue(String statusKey) {
    final status = statusKey.toLowerCase();
    if (status == 'completed') return Icons.check_circle_outline_rounded;
    if (status == 'processing') return Icons.autorenew_rounded;
    if (status == 'on-hold') return Icons.pause_circle_outline_rounded;
    if (status == 'cancelled' || status == 'canceled') return Icons.cancel_outlined;
    if (status == 'failed') return Icons.error_outline_rounded;
    if (status == 'pending') return Icons.hourglass_empty_rounded;
    if (status == 'trash') return Icons.delete_sweep_outlined;
    return Icons.help_outline_rounded;
  }

  String _getStatusText(String statusKey) {
    final statusOption = _allPossibleStatusDisplayInfo.firstWhere(
            (s) => s['value'] == statusKey.toLowerCase(),
        orElse: () => {"name": statusKey.capitalizeFirst()});
    return statusOption['name'] as String;
  }

  String _getUniqueCartItemId(String productId, int? variationId) {
    return variationId != null && variationId > 0
        ? '${productId}_$variationId'
        : productId;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);

    _historyScrollController.addListener(_onHistoryScroll);
    _searchHistoryController.addListener(_onHistorySearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        ref.read(orderHistoryProvider.notifier).getOrderHistory(refresh: true);
      } catch (e) {
        debugPrint("[OrderScreen] Error adding listener or loading data: $e");
      }
    });

    _historyScrollController.addListener(() {
      if ((_swipedOrderIdHistory != null || _expandedOrderIdHistory != null) &&
          _historyScrollController.position.isScrollingNotifier.value) {
        if (mounted) {
          final swipedId = _swipedOrderIdHistory;
          if (swipedId != null && _slidableControllers.containsKey(swipedId)) {
            _slidableControllers[swipedId]?.close();
          }
          setState(() {
            _swipedOrderIdHistory = null;
          });
        }
      }
    });
    _tabController.addListener(_handleTabChange);
  }

  void _onOrderOrCustomerChange() {
    if (mounted) setState(() {});
  }

  void _onHistoryScroll() {
    final historyState = ref.read(orderHistoryProvider);
    if (_historyScrollController.position.pixels >= _historyScrollController.position.maxScrollExtent - 300 &&
        historyState.canLoadMore &&
        !historyState.isLoadingMore &&
        !historyState.isLoading) {
      ref.read(orderHistoryProvider.notifier).getOrderHistory(
        searchTerm: _searchHistoryController.text.trim(),
        status: _selectedStatusFilter,
      );
    }
  }

  void _onHistorySearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        ref.read(orderHistoryProvider.notifier).getOrderHistory(
          searchTerm: _searchHistoryController.text.trim(),
          status: _selectedStatusFilter,
          refresh: true,
        );
      }
    });
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging ||
        (!_tabController.indexIsChanging && _tabController.index != _tabController.previousIndex)) {
      if (mounted) {
        // ✅ FIX: Cargar historial si está vacío al entrar a la pestaña
        if (_tabController.index == 1) {
          final historyState = ref.read(orderHistoryProvider);
          if (historyState.orders.isEmpty && !historyState.isLoading) {
            ref.read(orderHistoryProvider.notifier).getOrderHistory(
                searchTerm: _searchHistoryController.text.trim(),
                status: _selectedStatusFilter,
                refresh: true
            );
          }
        }

        final swipedId = _swipedOrderIdHistory;
        if (swipedId != null && _slidableControllers.containsKey(swipedId)) {
          _slidableControllers[swipedId]?.close();
        }
        setState(() {
          _swipedOrderIdHistory = null;
          _expandedOrderItemIdActual = null;
          if (_tabController.index != 1) {
            _expandedOrderIdHistory = null;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    // ✓ FASE 1 RIVERPOD: Ya no necesitamos removeListener con Riverpod
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchHistoryController.removeListener(_onHistorySearchChanged);
    _searchHistoryController.dispose();
    _historyScrollController.removeListener(_onHistoryScroll);
    _historyScrollController.dispose();
    _searchDebounce?.cancel();
    _slidableControllers.forEach((_, controller) => controller.dispose());
    _slidableControllers.clear();
    super.dispose();
  }

  Future<void> _deleteOrderItem(OrderItem item) async {
    if (!mounted) return;
    final orderNotifier = ref.read(currentOrderProvider.notifier);
    String uniqueItemId = item.variationId != null ? '${item.productId}_${item.variationId}' : item.productId;
    await orderNotifier.removeItem(uniqueItemId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Producto "${item.name}" eliminado del pedido.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _duplicateOrderItem(OrderItem item) async {
    if (!mounted) return;
    final orderNotifier = ref.read(currentOrderProvider.notifier);
    String uniqueItemId = item.variationId != null ? '${item.productId}_${item.variationId!}' : item.productId;
    await orderNotifier.duplicateOrderItem(uniqueItemId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Producto "${item.name}" duplicado en el pedido.'), backgroundColor: Colors.blueGrey),
      );
    }
  }

  Future<void> _updateOrderStatus(BuildContext buildContext, Order order, String newStatus, {bool isFromHistory = false}) async {
    final orderNotifier = ref.read(currentOrderProvider.notifier);
    final String displayOrderId = order.number ?? (order.id != null && order.id!.length > 6 ? order.id!.substring(0, 6) : order.id ?? "N/A");

    if (order.id == null || order.id!.startsWith('local_') || order.id == hiveCurrentOrderPendingKey) {
      bool localUpdateSuccess = await orderNotifier.updateOrderStatus(order.id ?? hiveCurrentOrderPendingKey, newStatus);
      if(localUpdateSuccess && mounted){
        ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(content: Text('Estado del pedido local #${order.id?.substring(0,6) ?? "Actual"} actualizado a "$newStatus".'), backgroundColor: Colors.blueGrey));
        if(isFromHistory) await ref.read(orderHistoryProvider.notifier).getOrderHistory(refresh: true);
        setState((){});
      } else if(mounted) {
        final currentState = ref.read(currentOrderProvider);
        final error = currentState.maybeWhen(data: (state) => state.error, orElse: () => null);
        ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(content: Text(error ?? 'No se pudo actualizar el estado local.'), backgroundColor: Colors.red));
      }
      return;
    }

    showDialog(context: buildContext, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    bool success = await orderNotifier.updateOrderStatus(order.id!, newStatus);

    if (mounted) {
      if (Navigator.of(buildContext, rootNavigator: true).canPop()) Navigator.of(buildContext, rootNavigator: true).pop();

      if (success) {
        await ref.read(orderHistoryProvider.notifier).getOrderHistory(refresh: true);
        setState(() {});
        ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(content: Text('Estado de Pedido #$displayOrderId actualizado a "${_getStatusText(newStatus)}".'), backgroundColor: Colors.green));
      } else {
        final currentState = ref.read(currentOrderProvider);
        final error = currentState.maybeWhen(data: (state) => state.error, orElse: () => null);
        ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(content: Text(error ?? 'No se pudo actualizar el estado.'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _showSaveOrderConfirmationDialog(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentState = ref.read(currentOrderProvider);
    final currentOrder = currentState.maybeWhen(
      data: (state) => state.order,
      orElse: () => null,
    );

    if (currentOrder == null || currentOrder.items.isEmpty) {
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('No hay productos en el pedido'), backgroundColor: Colors.orange));
      return;
    }
    const String defaultFinalStatus = 'completed';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar y Guardar Pedido'),
          content: const Text('El pedido se enviará a WooCommerce con estado "Completado". ¿Deseas continuar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('GUARDAR'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _saveOrder(context, defaultFinalStatus);
    }
  }

  Future<void> _saveOrder(BuildContext buildContext, String finalStatus) async {
    final orderNotifier = ref.read(currentOrderProvider.notifier);
    final scaffoldMessenger = ScaffoldMessenger.of(buildContext);
    showDialog(context: buildContext, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    String? resultId; String? finalMessage; Color? finalColor;

    try {
      resultId = await orderNotifier.saveOrder(finalStatus: finalStatus);
      final bool savedLocally = resultId != null && resultId.startsWith('local_');

      if (savedLocally) {
        finalMessage = 'Pedido guardado localmente (ID: ${resultId.length > 10 ? resultId.substring(6, 10) : resultId}...)';
        finalColor = Colors.blueGrey;
      } else if (resultId != null) {
        finalMessage = 'Pedido guardado exitosamente en el servidor.';
        finalColor = Colors.green;
      } else {
        final currentState = ref.read(currentOrderProvider);
        final error = currentState.maybeWhen(data: (state) => state.error, orElse: () => null);
        finalMessage = error ?? 'Error desconocido al guardar el pedido.';
        finalColor = Colors.red;
      }

      if (resultId != null && mounted) {
        await ref.read(orderHistoryProvider.notifier).getOrderHistory(refresh: true);
        if(!savedLocally) _tabController.animateTo(1);
        ref.read(customerProvider.notifier).clearSelectedCustomer();
      }

    } on ApiException catch (e) { if (mounted) { finalMessage = e.message; finalColor = Colors.red; }
    } on NetworkException catch (e) { if (mounted) { finalMessage = e.message; finalColor = Colors.orange.shade800; }
    } catch (e) { if (mounted) { finalMessage = "Error inesperado al guardar: ${e.toString()}"; finalColor = Colors.red; }
    } finally { if (mounted && Navigator.of(buildContext, rootNavigator: true).canPop()) { Navigator.of(buildContext, rootNavigator: true).pop(); } }

    if (mounted && finalMessage != null) {
      scaffoldMessenger.showSnackBar( SnackBar(content: Text(finalMessage), backgroundColor: finalColor, duration: const Duration(seconds: 3)), );
    }
  }

  void _onBottomNavTap(int index) {
    if (!mounted) return;
    setState(() => _currentBottomNavIndex = index);
    if (index == 0) {
      Routes.replaceWith(context, Routes.scanner);
    } else if (index == 1) {
      // ya estamos aquí
    }
  }

  Future<void> _loadOrderForEditing(BuildContext context, Order order) async {
    if (!mounted) return;
    final orderNotifier = ref.read(currentOrderProvider.notifier);
    await orderNotifier.loadOrderForEditing(order);
    _tabController.animateTo(0);
  }

  Future<void> _handlePdfAction(BuildContext context, Order order) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await PdfGenerator.printOrSharePdf(order, share: true);
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error generando PDF: ${e.toString()}'), backgroundColor: Colors.red));
    }
  }


  void _handleMoreOptionsForHistoryItem(BuildContext context, Order order) {
    final orderNotifier = ref.read(currentOrderProvider.notifier);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Duplicar Pedido'),
            onTap: () async {
              Navigator.pop(ctx);
              await orderNotifier.duplicateOrder(order);
              _tabController.animateTo(0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: const Text('Asignar a Cliente'),
            onTap: () {
              Navigator.pop(ctx);
              _showCustomerSearchForHistoryOrder(context, order);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Mover a Papelera'),
            onTap: () async {
              Navigator.pop(ctx);
              await _updateOrderStatus(context, order, 'trash', isFromHistory: true);
            },
          ),
        ],
      ),
    );
  }

  void _showChangeStatusDialogForOrder(BuildContext context, Order order, {bool isFromHistoryScreen = false}) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cambiar Estado de Pedido #${order.number ?? order.id?.substring(0, 6)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _allPossibleStatusDisplayInfo.map((statusOption) {
              return ListTile(
                title: Text(statusOption['name']),
                leading: Icon(Icons.circle, color: statusOption['color'], size: 16),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _updateOrderStatus(context, order, statusOption['value'], isFromHistory: isFromHistoryScreen);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showCustomerSearchForHistoryOrder(BuildContext context, Order order) {
    // Implementar la lógica para buscar y asignar un cliente a un pedido del historial.
  }

  // ✅ FASE 3: Modal para aplicar descuento a un item
  void _showDiscountModal(BuildContext context, OrderItem item) {
    final TextEditingController discountController = TextEditingController(
      text: (item.individualDiscount ?? 0) > 0 ? item.individualDiscount.toString() : '',
    );
    String discountType = 'fixed'; // 'fixed' o 'percent'

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Aplicar Descuento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Monto Fijo'),
                      value: 'fixed',
                      groupValue: discountType,
                      onChanged: (value) {
                        setState(() => discountType = value!);
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Porcentaje'),
                      value: 'percent',
                      groupValue: discountType,
                      onChanged: (value) {
                        setState(() => discountType = value!);
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: discountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: discountType == 'fixed' ? 'Descuento (₡)' : 'Descuento (%)',
                  hintText: '0',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(
                    discountType == 'fixed' ? Icons.attach_money : Icons.percent,
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Precio unitario: ${currencyFormat.format(item.price)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                'Cantidad: ${item.quantity}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Eliminar descuento
                final itemUniqueId = item.isVariation
                    ? '${item.productId}_${item.variationId!}'
                    : item.productId;
                ref.read(currentOrderProvider.notifier).applyItemDiscount(
                  uniqueItemId: itemUniqueId,
                  value: 0.0,
                  isPercentage: false,
                );
                Navigator.pop(dialogContext);
              },
              child: const Text('QUITAR DESCUENTO'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () {
                final discountValue = double.tryParse(discountController.text) ?? 0.0;
                if (discountValue > 0) {
                  final itemUniqueId = item.isVariation
                      ? '${item.productId}_${item.variationId!}'
                      : item.productId;

                  // ✅ applyItemDiscount maneja la conversión internamente
                  ref.read(currentOrderProvider.notifier).applyItemDiscount(
                    uniqueItemId: itemUniqueId,
                    value: discountValue,
                    isPercentage: discountType == 'percent',
                  );
                }
                Navigator.pop(dialogContext);
              },
              child: const Text('APLICAR'),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ FASE 3: Modal para cambiar variante de un item (placeholder - necesita implementación completa)
  void _showVariantsModal(BuildContext context, OrderItem item) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cambiar Variante'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.name),
            const SizedBox(height: 16),
            const Text(
              'Funcionalidad próximamente.\n\nPor ahora, elimina el item y agrega la variante correcta desde el escáner.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }

  // ✅ FASE 3: Guardar pedido como borrador
  Future<void> _saveDraft(BuildContext context, Order order) async {
    try {
      final storageService = getIt<StorageService>();

      final draft = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(), // Usar timestamp como ID
        'items': order.items.map((item) => {
          'product_id': item.productId,
          'variation_id': item.variationId,
          'name': item.name,
          'sku': item.sku,
          'quantity': item.quantity,
          'price': item.price,
          'discount': item.individualDiscount ?? 0.0,
          'subtotal': (item.price * item.quantity) - (item.individualDiscount ?? 0.0),
          'attributes': item.attributes,
        }).toList(),
        'customer': order.customerId != null ? {
          'id': order.customerId,
          'name': order.customerName,
        } : null,
        'totals': {
          'subtotal': order.subtotal,
          'discount': order.discount,
          'tax': order.tax,
          'total': order.total,
        },
        'createdAt': DateTime.now().toIso8601String(),
      };

      await storageService.saveDraftOrder(draft);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Borrador guardado exitosamente'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[OrderScreen] Error saving draft: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar borrador: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ FASE 3: Cargar borrador desde DraftOrdersScreen
  Future<void> _loadDraft(BuildContext context) async {
    final draft = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const DraftOrdersScreen(),
      ),
    );

    if (draft != null && mounted) {
      // TODO: Implementar carga de borrador en el pedido actual
      // Necesitará método en OrderNotifier para restaurar pedido desde draft
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Funcionalidad de cargar borrador próximamente'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ✅ QUOTE: Compartir cotización
  Future<void> _shareQuote(BuildContext context, Order order) async {
    if (order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega productos al pedido primero'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Obtener el servicio de cotizaciones
      final quoteService = getIt<QuoteShareService>();

      // Convertir OrderItems a QuoteItems
      final quoteItems = order.items.map((item) => QuoteItem(
        name: item.name,
        quantity: item.quantity,
        price: item.price,
        sku: item.sku,
      )).toList();

      // Obtener información del cliente si está disponible
      final customerState = ref.read(customerProvider);
      final customerName = customerState.selectedCustomerName != 'Cliente General'
          ? customerState.selectedCustomerName
          : null;

      // Generar número de cotización
      final now = DateTime.now();
      final quoteNumber = 'COT-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour}${now.minute}${now.second}';

      // Mostrar diálogo de compartir
      await showShareQuoteDialog(
        context: context,
        items: quoteItems,
        subtotal: order.subtotal,
        taxAmount: order.tax,
        total: order.total,
        quoteShareService: quoteService,
        customerName: customerName,
        customerPhone: null,  // No disponible en CustomerState
        customerEmail: null,  // No disponible en CustomerState
        quoteNumber: quoteNumber,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al preparar cotización: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    bool canPopOrderScreen = Navigator.canPop(context);
    final appState = ref.watch(appStateNotifierProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppHeader(
        title: 'Pedidos',
        showBackButton: (_tabController.index == 0 && canPopOrderScreen) || (_tabController.index != 0),
        onBackPressed: () {
          if (_tabController.index == 0) {
            if (canPopOrderScreen) { Navigator.pop(context); } else { Routes.replaceWith(context, Routes.scanner); }
          } else { _tabController.animateTo(0); }
        },
        showCartButton: false, showSettingsButton: true,
        onSettingsPressed: () => Routes.navigateTo(context, Routes.settings),
      ),
      body: Column(
        children: [
          Consumer(builder: (context, ref, child) {
            final appState = ref.watch(appStateNotifierProvider);
            if (!appState.isOnline) {
              return Container(
                  color: Colors.orange.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text('Modo sin conexión', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500))
                      ]
                  )
              );
            }
            return const SizedBox.shrink();
          }),
          Container(
            color: theme.canvasColor,
            child: TabBar(
              controller: _tabController, labelColor: theme.primaryColor, unselectedLabelColor: Colors.grey.shade700, indicatorColor: theme.primaryColor, indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: const [ Tab(text: 'PEDIDO ACTUAL'), Tab(text: 'HISTORIAL'), ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [ _buildCurrentOrderTabWithStickyFooter(context), _buildOrderHistoryTab(context), ],
                ),
                if (appState.appError != null) Align( alignment: Alignment.bottomCenter, child: MaterialBanner( padding: const EdgeInsets.all(10), content: Text(appState.appError!, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red.shade700, actions: [ TextButton( child: const Text('CERRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: () => ref.read(appStateNotifierProvider.notifier).clearError(), ), ], ), )
                else if (appState.appNotification != null) Align( alignment: Alignment.bottomCenter, child: MaterialBanner( padding: const EdgeInsets.all(10), content: Text(appState.appNotification!, style: const TextStyle(color: Colors.black87)), backgroundColor: Colors.blueGrey.shade100, actions: [ TextButton( child: const Text('CERRAR', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)), onPressed: () { ref.read(appStateNotifierProvider.notifier).clearNotification(); }, ), ], ), ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: const DialFloatingActionButton(),
      floatingActionButtonLocation: const LoweredCenterDockedFabLocation(downwardShift: 10.0),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(), notchMargin: 8.0, clipBehavior: Clip.antiAlias, color: theme.bottomAppBarTheme.color ?? theme.colorScheme.surface, elevation: 8.0,
        child: SizedBox( height: kBottomNavigationBarHeight, child: Row( children: <Widget>[ _buildBottomNavItem(context: context, icon: Icons.qr_code_scanner, label: 'CÓDIGO', itemIndex: 0, onTap: _onBottomNavTap), const Spacer(), _buildBottomNavItem(context: context, icon: Icons.receipt_long_outlined, label: 'PEDIDOS', itemIndex: 1, onTap: _onBottomNavTap), ], ), ),
      ),
    );
  }

  Widget _buildCurrentOrderTabWithStickyFooter(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final orderState = ref.watch(currentOrderProvider);

        return orderState.when(
          data: (state) {
            final order = state.order;
            if (order == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Pedido Actual", style: Theme.of(context).textTheme.titleLarge),
                              Flexible(
                                child: InkWell(
                                  onTap: () async {
                                    // ✅ CLIENTES: Usar CustomerSelectionDialog con WooCommerce
                                    final Customer? selectedCustomer = await showDialog<Customer>(
                                      context: context,
                                      builder: (context) => CustomerSelectionDialog(
                                        selectedCustomer: order.customerId != null && order.customerId!.isNotEmpty
                                          ? Customer(
                                              id: int.tryParse(order.customerId!) ?? 0,
                                              email: '',
                                              firstName: order.customerName?.split(' ').first ?? '',
                                              lastName: order.customerName?.split(' ').skip(1).join(' ') ?? '',
                                            )
                                          : null,
                                      ),
                                    );

                                    if (selectedCustomer != null && mounted) {
                                      // Actualizar orden con cliente seleccionado
                                      ref.read(currentOrderProvider.notifier).updateOrderCustomer(
                                        selectedCustomer.id.toString(),
                                        selectedCustomer.name,
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person_outline, size: 20),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            order.customerName ?? 'Cliente General',
                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        const Icon(Icons.arrow_drop_down, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                      if (order.items.isEmpty)
                        const SliverFillRemaining(
                          child: Center(
                            child: Text("Añade productos desde el escáner"),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              final item = order.items[index];
                              final uniqueItemId = _getUniqueCartItemId(item.productId, item.variationId);

                              // ✅ FASE 3: Dismissible para eliminar deslizando
                              return Dismissible(
                                key: ValueKey(uniqueItemId),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                                confirmDismiss: (direction) async {
                                  return await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Eliminar Producto'),
                                      content: Text(
                                        '¿Eliminar "${item.name}" del pedido?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext, false),
                                          child: const Text('CANCELAR'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(dialogContext, true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          child: const Text('ELIMINAR'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                onDismissed: (direction) {
                                  _deleteOrderItem(item);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${item.name} eliminado'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: CurrentOrderItemCard(
                                  item: item,
                                  currencyFormat: currencyFormat,
                                  onDelete: () => _deleteOrderItem(item),
                                  onDuplicate: () => _duplicateOrderItem(item),
                                  isExpanded: _expandedOrderItemIdActual == uniqueItemId,
                                  onToggleExpand: () {
                                    if (mounted) setState(() => _expandedOrderItemIdActual = _expandedOrderItemIdActual == uniqueItemId ? null : uniqueItemId);
                                  },
                                  onShowVariantsModal: (OrderItem item) {
                                    _showVariantsModal(context, item);
                                  },
                                  onShowDiscountModal: (OrderItem item) {
                                    _showDiscountModal(context, item);
                                  },
                                ),
                              );
                            },
                            childCount: order.items.length,
                          ),
                        ),
                    ],
                  ),
                ),
                if (order.items.isNotEmpty) _buildBottomActionBar(context, order, state.taxRate), // ✅ FASE 3: Pasar order y taxRate
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Error: $error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ FASE 3: Bottom bar mejorado con desglose expandible
  Widget _buildBottomActionBar(BuildContext context, Order order, double taxRate) {
    final currencyFormat = NumberFormat.currency(symbol: '₡', decimalDigits: 0);
    return Material(
      elevation: 8,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Detalles expandibles (Totales y Borradores)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 8),
                    const Text('Ver detalles', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      children: [
                        // Botones de acción: Borrador y Cargar
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _saveDraft(context, order),
                                icon: const Icon(Icons.save_outlined, size: 18),
                                label: const Text('Guardar Borrador', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _loadDraft(context),
                                icon: const Icon(Icons.folder_open, size: 18),
                                label: const Text('Cargar Borrador', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        // Desglose de cálculos
                        _buildCalculationRow('Subtotal:', order.subtotal, isSubtotal: true),
                        if (order.discount > 0)
                          _buildCalculationRow('Descuento:', -order.discount, isDiscount: true),
                        _buildCalculationRow('Impuestos (${(taxRate * 100).toStringAsFixed(0)}%):', order.tax, isTax: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Total y botones de acción (siempre visible)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("TOTAL", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                      Text(
                        currencyFormat.format(order.total),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Botones de acción en una barra horizontal
                  Row(
                    children: [
                      // Botón Compartir
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: order.items.isEmpty ? null : () => _shareQuote(context, order),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Compartir', style: TextStyle(fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Botón Finalizar
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: order.items.isEmpty ? null : () => _showSaveOrderConfirmationDialog(context),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text("FINALIZAR", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ FASE 3: Helper para mostrar fila de cálculo
  Widget _buildCalculationRow(String label, double value, {bool isSubtotal = false, bool isDiscount = false, bool isTax = false}) {
    Color? valueColor;
    if (isDiscount) valueColor = Colors.green.shade700;
    if (isTax) valueColor = Colors.orange.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: isSubtotal ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            currencyFormat.format(value),
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSubtotal ? FontWeight.w600 : FontWeight.w500,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// ✓ OPTIMIZADO: Usa Selector para evitar rebuilds innecesarios
  Widget _buildOrderHistoryTab(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildHistoryFilters(context),
        Expanded(
          // ✓ FASE 1 RIVERPOD: Consumer observa orderHistoryProvider
          child: Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(orderHistoryProvider);

              // Estado de carga inicial
              if (state.isLoading && state.orders.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              // Estado de error inicial
              if (state.error != null && state.orders.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      state.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                );
              }

              // Lista vacía
              if (state.orders.isEmpty) {
                return const Center(
                  child: Text("No se encontraron pedidos para los filtros aplicados."),
                );
              }

              // Lista con datos
              return RefreshIndicator(
                onRefresh: () => ref.read(orderHistoryProvider.notifier).getOrderHistory(
                  searchTerm: _searchHistoryController.text.trim(),
                  status: _selectedStatusFilter,
                  refresh: true,
                ),
                child: ListView.builder(
                  controller: _historyScrollController,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
                  itemCount: state.orders.length + (state.isLoadingMore ? 1 : 0),
                  itemBuilder: (ctx, index) {
                    // Indicador de carga al final
                    if (index == state.orders.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final order = state.orders[index];
                    final orderKey = order.id ?? 'local_${order.hashCode}';
                    _slidableControllers.putIfAbsent(orderKey, () => SlidableController(this));

                    return HistoryOrderItemCard(
                      key: ValueKey('history_order_card_$orderKey'),
                      order: order,
                      currencyFormat: currencyFormat,
                      dateTimeFormat: dateTimeFormat,
                      slidableController: _slidableControllers[orderKey],
                      onEdit: () { _loadOrderForEditing(context, order); _slidableControllers[orderKey]?.close(); },
                      onPdf: () { _handlePdfAction(context, order); _slidableControllers[orderKey]?.close(); },
                      onMore: () { _handleMoreOptionsForHistoryItem(context, order); },
                      onChangeStatusAction: () { _showChangeStatusDialogForOrder(context, order, isFromHistoryScreen: true); },
                      isExpanded: _expandedOrderIdHistory == orderKey,
                      onExpansionChanged: (isExpanding) {
                        if (mounted) {
                          setState(() {
                            _expandedOrderIdHistory = isExpanding ? orderKey : null;
                            if (!isExpanding && _slidableControllers.containsKey(orderKey)) {
                              _slidableControllers[orderKey]?.close();
                            }
                          });
                        }
                      },
                      statusTextBuilder: _getStatusText,
                      statusColorBuilder: _getStatusColor,
                      statusIconBuilder: _getIconForStatusValue,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryFilters(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchHistoryController,
              decoration: InputDecoration(
                hintText: 'Buscar por ID, nombre o email...',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 22, color: Colors.grey.shade600),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: theme.primaryColor, width: 1.5)),
                filled: true,
                fillColor: theme.scaffoldBackgroundColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                suffixIcon: _searchHistoryController.text.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear, size: 20, color: Colors.grey.shade600),
                  onPressed: () => _searchHistoryController.clear(),
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                )
                    : null,
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (String result) {
              if (_selectedStatusFilter != result) {
                setState(() => _selectedStatusFilter = result);
                _onHistorySearchChanged();
              }
            },
            itemBuilder: (BuildContext context) => _orderStatusesForFilterUI.entries.map((entry) {
              return PopupMenuItem<String>(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_list, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 4),
                  Text(_orderStatusesForFilterUI[_selectedStatusFilter] ?? '', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int itemIndex,
    required void Function(int) onTap,
  }) {
    final bool isSelected = _currentBottomNavIndex == itemIndex;
    final Color color = isSelected ? Theme.of(context).primaryColor : Colors.grey.shade600;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(itemIndex),
        borderRadius: BorderRadius.circular(4.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}