// lib/screens/order_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:collection/collection.dart';

import '../models/order.dart' show Order, OrderItem, StringExtension;
import '../models/product.dart' as app_product;
import '../providers/customer_provider.dart';
import '../providers/order_provider.dart';
import '../providers/app_state_provider.dart';
import '../repositories/product_repository.dart';
import '../locator.dart';

import '../widgets/app_header.dart';
import '../widgets/dial_floating_action_button.dart';
import '../widgets/custom_fab_location.dart';
import '../config/constants.dart';
import '../config/routes.dart';
import 'customer_edit_screen.dart';
import '../utils/pdf_generator.dart';

import '../widgets/order/current_order_item_card.dart';
import '../widgets/order/history_order_item_card.dart';

import '../services/woocommerce_service.dart';

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


class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> with TickerProviderStateMixin {
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
        context.read<OrderProvider>().addListener(_onOrderOrCustomerChange);
        context.read<OrderProvider>().getOrderHistory(refresh: true);
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
    final provider = context.read<OrderProvider>();
    if (_historyScrollController.position.pixels >= _historyScrollController.position.maxScrollExtent - 300 &&
        provider.historyCanLoadMore &&
        !provider.historyIsLoadingMore &&
        !provider.historyIsLoading) {
      provider.getOrderHistory(
        searchTerm: _searchHistoryController.text.trim(),
        status: _selectedStatusFilter,
      );
    }
  }

  void _onHistorySearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        context.read<OrderProvider>().getOrderHistory(
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
    try {
      context.read<OrderProvider>().removeListener(_onOrderOrCustomerChange);
    } catch(e) { debugPrint("[OrderScreen] Error removing listener in dispose: $e");}
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
    final orderProvider = context.read<OrderProvider>();
    String uniqueItemId = item.variationId != null ? '${item.productId}_${item.variationId}' : item.productId;
    await orderProvider.removeItem(uniqueItemId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Producto "${item.name}" eliminado del pedido.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _duplicateOrderItem(OrderItem item) async {
    if (!mounted) return;
    final orderProvider = context.read<OrderProvider>();
    String uniqueItemId = item.variationId != null ? '${item.productId}_${item.variationId!}' : item.productId;
    await orderProvider.duplicateOrderItem(uniqueItemId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Producto "${item.name}" duplicado en el pedido.'), backgroundColor: Colors.blueGrey),
      );
    }
  }

  Future<void> _updateOrderStatus(BuildContext buildContext, Order order, String newStatus, {bool isFromHistory = false}) async {
    final orderProvider = Provider.of<OrderProvider>(buildContext, listen: false);
    final String displayOrderId = order.number ?? (order.id != null && order.id!.length > 6 ? order.id!.substring(0, 6) : order.id ?? "N/A");

    if (order.id == null || order.id!.startsWith('local_') || order.id == hiveCurrentOrderPendingKey) {
      bool localUpdateSuccess = await orderProvider.updateOrderStatus(order.id ?? hiveCurrentOrderPendingKey, newStatus);
      if(localUpdateSuccess && mounted){
        ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(content: Text('Estado del pedido local #${order.id?.substring(0,6) ?? "Actual"} actualizado a "$newStatus".'), backgroundColor: Colors.blueGrey));
        if(isFromHistory) await orderProvider.getOrderHistory(refresh: true);
        setState((){});
      } else if(mounted) {
        ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(content: Text(orderProvider.errorMessage ?? 'No se pudo actualizar el estado local.'), backgroundColor: Colors.red));
      }
      return;
    }

    showDialog(context: buildContext, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    bool success = await orderProvider.updateOrderStatus(order.id!, newStatus);

    if (mounted) {
      if (Navigator.of(buildContext, rootNavigator: true).canPop()) Navigator.of(buildContext, rootNavigator: true).pop();

      if (success) {
        await orderProvider.getOrderHistory(refresh: true);
        setState(() {});
        ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(content: Text('Estado de Pedido #$displayOrderId actualizado a "${_getStatusText(newStatus)}".'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(content: Text(orderProvider.errorMessage ?? 'No se pudo actualizar el estado.'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _showSaveOrderConfirmationDialog(BuildContext context, OrderProvider orderProvider) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (orderProvider.currentOrder == null || orderProvider.currentOrder!.items.isEmpty) {
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
      await _saveOrder(context, orderProvider, defaultFinalStatus);
    }
  }

  Future<void> _saveOrder(BuildContext buildContext, OrderProvider orderProvider, String finalStatus) async {
    final scaffoldMessenger = ScaffoldMessenger.of(buildContext);
    showDialog(context: buildContext, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    String? resultId; String? finalMessage; Color? finalColor;

    try {
      resultId = await orderProvider.saveOrder(finalStatus: finalStatus);
      final bool savedLocally = resultId != null && resultId.startsWith('local_');

      if (savedLocally) {
        finalMessage = 'Pedido guardado localmente (ID: ${resultId.length > 10 ? resultId.substring(6, 10) : resultId}...)';
        finalColor = Colors.blueGrey;
      } else if (resultId != null) {
        finalMessage = 'Pedido guardado exitosamente en el servidor.';
        finalColor = Colors.green;
      } else {
        finalMessage = orderProvider.errorMessage ?? 'Error desconocido al guardar el pedido.';
        finalColor = Colors.red;
      }

      if (resultId != null && mounted) {
        await orderProvider.getOrderHistory(refresh: true);
        if(!savedLocally) _tabController.animateTo(1);
        context.read<CustomerProvider>().clearSelectedCustomer();
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
    final orderProvider = context.read<OrderProvider>();
    await orderProvider.loadOrderForEditing(order);
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
    final orderProvider = context.read<OrderProvider>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Duplicar Pedido'),
            onTap: () async {
              Navigator.pop(ctx);
              await orderProvider.duplicateOrder(order);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    bool canPopOrderScreen = Navigator.canPop(context);
    final appState = context.watch<AppStateProvider>();

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
          Consumer<AppStateProvider>( builder: (context, appState, child) { if (appState.connectionStatus == ConnectionStatus.offline) { return Container( color: Colors.orange.shade800, padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 16), child: const Row( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14), SizedBox(width: 6), Text('Modo sin conexión', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500)) ] ) ); } return const SizedBox.shrink(); }, ),
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
                if (appState.error != null) Align( alignment: Alignment.bottomCenter, child: MaterialBanner( padding: const EdgeInsets.all(10), content: Text(appState.error!, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red.shade700, actions: [ TextButton( child: const Text('CERRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: () => context.read<AppStateProvider>().clearError(), ), ], ), )
                else if (appState.notification != null) Align( alignment: Alignment.bottomCenter, child: MaterialBanner( padding: const EdgeInsets.all(10), content: Text(appState.notification!, style: const TextStyle(color: Colors.black87)), backgroundColor: Colors.blueGrey.shade100, actions: [ TextButton( child: const Text('CERRAR', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)), onPressed: () { context.read<AppStateProvider>().clearNotification(); }, ), ], ), ),
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
    return Consumer<OrderProvider>(
      builder: (context, orderProvider, _) {
        final order = orderProvider.currentOrder;
        if (order == null || orderProvider.isLoading) {
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
                          InkWell(
                            onTap: () async {
                              final selectedCustomer = await Routes.navigateTo(context, Routes.customerSearch);
                              if(selectedCustomer is Map<String, dynamic> && mounted){
                                context.read<OrderProvider>().updateOrderCustomer(selectedCustomer['id'], selectedCustomer['name']);
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.person_outline, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    order.customerName ?? 'Cliente General',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  const Icon(Icons.arrow_drop_down, size: 20),
                                ],
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
                          return CurrentOrderItemCard(
                            item: item,
                            currencyFormat: currencyFormat,
                            onDelete: () => _deleteOrderItem(item),
                            onDuplicate: () => _duplicateOrderItem(item),
                            isExpanded: _expandedOrderItemIdActual == uniqueItemId,
                            onToggleExpand: () {
                              if (mounted) setState(() => _expandedOrderItemIdActual = _expandedOrderItemIdActual == uniqueItemId ? null : uniqueItemId);
                            },
                            onShowVariantsModal: (OrderItem item) {
                            },
                            onShowDiscountModal: (OrderItem item) {
                            },
                          );
                        },
                        childCount: order.items.length,
                      ),
                    ),
                ],
              ),
            ),
            if (order.items.isNotEmpty) _buildBottomActionBar(context, order.total),
          ],
        );
      },
    );
  }

  Widget _buildBottomActionBar(BuildContext context, double total) {
    return Material(
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("TOTAL", style: TextStyle(fontSize: 13, color: Colors.grey)),
                Text(
                  currencyFormat.format(total),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () => _showSaveOrderConfirmationDialog(context, context.read<OrderProvider>()),
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text("GUARDAR PEDIDO"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderHistoryTab(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildHistoryFilters(context),
        Expanded(
          child: (orderProvider.historyIsLoading && orderProvider.historyOrders.isEmpty)
              ? const Center(child: CircularProgressIndicator())
              : (orderProvider.historyError != null && orderProvider.historyOrders.isEmpty)
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(orderProvider.historyError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700))))
              : (orderProvider.historyOrders.isEmpty)
              ? const Center(child: Text("No se encontraron pedidos para los filtros aplicados."))
              : RefreshIndicator(
            onRefresh: () => orderProvider.getOrderHistory(
              searchTerm: _searchHistoryController.text.trim(),
              status: _selectedStatusFilter,
              refresh: true,
            ),
            child: ListView.builder(
              controller: _historyScrollController,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
              itemCount: orderProvider.historyOrders.length + (orderProvider.historyIsLoadingMore ? 1 : 0),
              itemBuilder: (ctx, index) {
                if (index == orderProvider.historyOrders.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final order = orderProvider.historyOrders[index];
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