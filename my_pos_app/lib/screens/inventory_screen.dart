// lib/screens/inventory_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/inventory_movement.dart';
import '../providers/inventory_provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/label_provider.dart';

import '../widgets/app_header.dart';
import '../widgets/dial_floating_action_button.dart';
import '../widgets/custom_fab_location.dart';
import '../config/routes.dart';

import '../models/inventory_movement_extensions.dart';
import './inventory_adjustment_form_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _historySearchController = TextEditingController();
  final ScrollController _historyScrollController = ScrollController();
  Timer? _historySearchDebounce;
  bool _showHistoryView = false;

  final dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm', 'es_CR');

  @override
  void initState() {
    super.initState();
    _historyScrollController.addListener(_onHistoryScroll);
    _historySearchController.addListener(_onHistorySearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _toggleView(true); // Iniciar por defecto en la vista de historial
      }
    });
  }

  @override
  void dispose() {
    _historySearchController.removeListener(_onHistorySearchChanged);
    _historyScrollController.removeListener(_onHistoryScroll);
    _historySearchController.dispose();
    _historyScrollController.dispose();
    _historySearchDebounce?.cancel();
    super.dispose();
  }

  void _onHistoryScroll() {
    final provider = context.read<InventoryProvider>();
    if (_historyScrollController.position.pixels >= _historyScrollController.position.maxScrollExtent - 300 &&
        provider.canLoadMoreMovements &&
        !provider.isLoadingMoreMovements &&
        !provider.isLoadingMovements) {
      provider.loadInventoryMovements(searchTerm: _historySearchController.text.trim());
    }
  }

  void _onHistorySearchChanged() {
    _historySearchDebounce?.cancel();
    _historySearchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        context.read<InventoryProvider>().loadInventoryMovements(
          searchTerm: _historySearchController.text.trim(),
          refresh: true,
        );
      }
    });
  }

  void _toggleView(bool showHistory) {
    if (!mounted) return;
    setState(() {
      _showHistoryView = showHistory;
      if (_showHistoryView) {
        FocusScope.of(context).unfocus();
        context.read<InventoryProvider>().loadInventoryMovements(refresh: true);
      } else {
        _historySearchController.clear();
      }
    });
  }

  void _navigateToAdjustmentScreen(BuildContext context, String operationType, {String? specificMovementReasonValue}) {
    Navigator.pushNamed(
      context,
      Routes.inventoryAdjustmentForm,
      arguments: InventoryAdjustmentFormScreenArguments(
        operationType: operationType,
        initialReasonValue: specificMovementReasonValue,
      ),
    ).then((success) {
      if (success == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajuste de inventario procesado.'), backgroundColor: Colors.green),
        );
        if (_showHistoryView) {
          context.read<InventoryProvider>().loadInventoryMovements(refresh: true);
        }
      } else if (success is String && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resultado del ajuste: $success'), backgroundColor: Colors.orange),
        );
      }
    });
  }

  void _showResetStockConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resetear Stock a Cero'),
        content: const Text(
          '¡ADVERTENCIA! Esta acción intentará poner en CERO el stock de TODOS los productos. Se activará la gestión de inventario si es necesario. Esta acción se ejecutará en segundo plano y no se puede cancelar. ¿Estás seguro?',
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<InventoryProvider>().resetAllStockToZero();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Iniciando reseteo de stock en segundo plano...'), backgroundColor: Colors.blueGrey),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('SÍ, RESETEAR TODO'),
          ),
        ],
      ),
    );
  }

  void _showActivateStockMgmtConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activar Gestión de Stock'),
        content: const Text('Esta acción activará la "Gestión de inventario" para todos los productos variables y sus variaciones. Esto es útil para asegurar un control de stock preciso. La tarea se ejecutará en segundo plano.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<InventoryProvider>().activateManageStockForAllVariables();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Iniciando activación en segundo plano...'), backgroundColor: Colors.blueGrey),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.blue.shade800),
            child: const Text('SÍ, ACTIVAR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventoryProvider = context.watch<InventoryProvider>();
    final appState = context.watch<AppStateProvider>();
    final isRootInventoryView = !_showHistoryView;
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppHeader(
        title: _showHistoryView ? 'Historial de Inventario' : 'Centro de Inventario',
        showBackButton: !isRootInventoryView,
        onBackPressed: _showHistoryView ? () => _toggleView(false) : null,
        showCartButton: true,
        showSettingsButton: true,
      ),
      body: Column(
        children: [
          if (appState.connectionStatus == ConnectionStatus.offline)
            Container(
              color: Colors.orange.shade800,
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text('Modo sin conexión', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          if (inventoryProvider.isBackgroundTaskRunning)
            Container(
              color: Colors.blueGrey.shade700,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(inventoryProvider.backgroundTaskMessage ?? 'Procesando...', style: const TextStyle(color: Colors.white, fontSize: 13))),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _showHistoryView
                ? _buildInventoryHistoryView(context, inventoryProvider)
                : _buildOperationsCenter(context),
          ),
        ],
      ),
      floatingActionButton: const DialFloatingActionButton(),
      floatingActionButtonLocation: const LoweredCenterDockedFabLocation(downwardShift: 10.0),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        clipBehavior: Clip.antiAlias,
        color: theme.bottomAppBarTheme.color ?? theme.colorScheme.surface,
        elevation: 8.0,
        child: SizedBox(
          height: kBottomNavigationBarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _buildBottomNavItem(context: context, icon: Icons.qr_code_scanner, label: 'CÓDIGO', itemIndex: 0),
              const Spacer(),
              _buildBottomNavItem(context: context, icon: Icons.receipt_long_outlined, label: 'PEDIDOS', itemIndex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOperationsCenter(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              "Operaciones de Inventario",
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Text(
            "Gestiona el stock de tus productos de forma rápida y sencilla.",
            style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _OperationButton(
                  icon: Icons.add_business_outlined,
                  label: "Registrar Entrada",
                  description: "Aumentar stock por compras, devoluciones.",
                  onPressed: () => _navigateToAdjustmentScreen(context, 'entry', specificMovementReasonValue: InventoryMovementType.supplierReceipt.name),
                  theme: theme,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _OperationButton(
                  icon: Icons.remove_shopping_cart_outlined,
                  label: "Registrar Salida",
                  description: "Disminuir stock por mermas, daños.",
                  onPressed: () => _navigateToAdjustmentScreen(context, 'exit', specificMovementReasonValue: InventoryMovementType.damageOrLoss.name),
                  theme: theme,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _OperationButton(
                  icon: Icons.rule_folder_outlined,
                  label: "Conteo/Ajuste Físico",
                  description: "Corregir stock actual por conteo.",
                  onPressed: () => _navigateToAdjustmentScreen(context, 'stockTake', specificMovementReasonValue: InventoryMovementType.stockCorrection.name),
                  theme: theme,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _OperationButton(
                  icon: Icons.manage_search_outlined,
                  label: "Ver Historial",
                  description: "Consultar movimientos pasados.",
                  onPressed: () => _toggleView(true),
                  theme: theme,
                  color: Colors.deepPurple.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              "Opciones Avanzadas",
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ),
          _AdvancedOperationButton(
            icon: Icons.file_upload,
            label: "Importar Ajuste desde CSV",
            description: "Actualiza masivamente el stock subiendo un archivo CSV.",
            onPressed: () => Navigator.pushNamed(context, Routes.inventoryCsvImport),
            theme: theme,
            color: Colors.teal,
          ),
          const SizedBox(height: 12),
          _AdvancedOperationButton(
            icon: Icons.dynamic_feed_outlined,
            label: "Activar Gestión de Stock para Variables",
            description: "Asegura que todos los productos con variantes gestionen inventario.",
            onPressed: () => _showActivateStockMgmtConfirmDialog(context),
            theme: theme,
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 12),
          _AdvancedOperationButton(
            icon: Icons.cleaning_services_outlined,
            label: "Resetear Stock a Cero",
            description: "Pone a cero el inventario de todos los productos (¡Usar con precaución!).",
            onPressed: () => _showResetStockConfirmDialog(context),
            theme: theme,
            color: Colors.orange.shade800,
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryHistoryView(BuildContext context, InventoryProvider provider) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
          child: TextField(
            controller: _historySearchController,
            decoration: InputDecoration(
              hintText: 'Buscar en historial...',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 22, color: Colors.grey.shade600),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide(color: theme.primaryColor, width: 1.5)),
              filled: true,
              fillColor: theme.scaffoldBackgroundColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              suffixIcon: _historySearchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, size: 20, color: Colors.grey.shade600),
                onPressed: () => _historySearchController.clear(),
                splashRadius: 20,
                padding: EdgeInsets.zero,
              ) : null,
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
        Expanded(
          child: (provider.isLoadingMovements && provider.inventoryMovements.isEmpty)
              ? const Center(child: CircularProgressIndicator())
              : (provider.movementsError != null && provider.inventoryMovements.isEmpty)
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(provider.movementsError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700))))
              : (provider.inventoryMovements.isEmpty)
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                _historySearchController.text.isNotEmpty ? 'No hay movimientos que coincidan con tu búsqueda.' : 'Aún no hay movimientos de inventario registrados.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ),
          )
              : RefreshIndicator(
            onRefresh: () => provider.loadInventoryMovements(
              searchTerm: _historySearchController.text,
              refresh: true,
            ),
            child: ListView.builder(
              controller: _historyScrollController,
              padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 80.0),
              itemCount: provider.inventoryMovements.length + (provider.isLoadingMoreMovements ? 1 : 0),
              itemBuilder: (ctx, index) {
                if (index == provider.inventoryMovements.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final movement = provider.inventoryMovements[index];
                final String movementTypeDisplayName = movement.type.displayName;
                final IconData movementTypeIcon = _getIconForMovementType(movement.type);
                final Color typeColor = _getColorForMovementType(theme, movement.type);
                final int totalItemsAffected = movement.items.length;
                final int totalQuantityChange = movement.items.fold(0, (sum, item) => sum + item.quantityChanged);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 4.0),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: ValueKey('movement_${movement.id}'),
                    backgroundColor: theme.colorScheme.surface.withOpacity(0.5),
                    collapsedBackgroundColor: theme.cardColor,
                    leading: CircleAvatar(
                      backgroundColor: typeColor.withOpacity(0.15),
                      child: Icon(movementTypeIcon, size: 22, color: typeColor),
                    ),
                    title: Text(
                        movement.description.isNotEmpty ? movement.description : movementTypeDisplayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)
                    ),
                    subtitle: Text(
                        "Por: ${movement.userName ?? 'N/A'}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700)
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          dateTimeFormat.format(movement.date.toLocal()),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (totalQuantityChange > 0 ? "+" : "") + totalQuantityChange.toString() + " uds.",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: totalQuantityChange == 0 ? Colors.blueGrey : (totalQuantityChange > 0 ? Colors.green.shade700 : Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(movement.type.displayName, style: TextStyle(fontSize: 11.5, color: typeColor, fontWeight: FontWeight.bold)),
                                Text('$totalItemsAffected producto(s)', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
                              ],
                            ),
                            const Divider(height: 16, thickness: 0.5),
                            ...movement.items.map((item) {
                              final String stockChangeString = (item.quantityChanged > 0 ? "+" : "") + item.quantityChanged.toString();
                              final Color stockChangeColor = item.quantityChanged > 0 ? Colors.green.shade700 : Colors.red.shade700;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.productName,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'SKU: ${item.sku.isNotEmpty ? item.sku : "N/A"}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${item.stockBefore ?? "--"} ➔ ${item.stockAfter ?? "--"}',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: stockChangeColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        stockChangeString,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: stockChangeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            const Divider(height: 16, thickness: 0.5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.print_outlined, size: 20),
                                  label: const Text('Enviar a Impresión'),
                                  onPressed: () async {
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (BuildContext dialogContext) => const AlertDialog(
                                        content: Row(children: [
                                          CircularProgressIndicator(),
                                          SizedBox(width: 24),
                                          Text("Preparando etiquetas..."),
                                        ]),
                                      ),
                                    );

                                    final labelProvider = context.read<LabelProvider>();
                                    final itemsAddedCount = await labelProvider.addMovementItemsToQueue(movement);

                                    if (!mounted) return;
                                    Navigator.of(context, rootNavigator: true).pop();

                                    if (itemsAddedCount > 0) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('$itemsAddedCount producto(s) añadidos a la cola de impresión.'),
                                          backgroundColor: Colors.green,
                                          action: SnackBarAction(
                                            label: 'IR A COLA',
                                            onPressed: () {
                                              Navigator.pushNamed(context, Routes.labelPrinting);
                                            },
                                          ),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('No se añadieron productos (solo se añaden los que tuvieron aumento de stock).'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  IconData _getIconForMovementType(InventoryMovementType type) {
    switch (type) {
      case InventoryMovementType.sale: return Icons.shopping_cart_checkout_rounded;
      case InventoryMovementType.massExit: return Icons.remove_circle_outline_rounded;
      case InventoryMovementType.transferOut: return Icons.north_east_rounded;
      case InventoryMovementType.damageOrLoss: return Icons.broken_image_outlined;
      case InventoryMovementType.refund: return Icons.assignment_return_outlined;
      case InventoryMovementType.stockReceipt:
      case InventoryMovementType.supplierReceipt:
        return Icons.inventory_2_outlined;
      case InventoryMovementType.transferIn: return Icons.south_west_rounded;
      case InventoryMovementType.massEntry: return Icons.add_circle_outline_rounded;
      case InventoryMovementType.customerReturnMass: return Icons.people_alt_outlined;
      case InventoryMovementType.manualAdjustment:
      case InventoryMovementType.stockCorrection:
      case InventoryMovementType.massManualAdjustment:
        return Icons.edit_note_outlined;
      case InventoryMovementType.initialStock: return Icons.fiber_new_outlined;
      case InventoryMovementType.toTrash: return Icons.delete_sweep_outlined;
      case InventoryMovementType.unknown:
      default:
        return Icons.sync_alt_outlined;
    }
  }
  Color _getColorForMovementType(ThemeData theme, InventoryMovementType type) {
    switch (type) {
      case InventoryMovementType.sale:
      case InventoryMovementType.massExit:
      case InventoryMovementType.transferOut:
      case InventoryMovementType.damageOrLoss:
      case InventoryMovementType.toTrash:
        return Colors.red.shade600;
      case InventoryMovementType.refund:
      case InventoryMovementType.stockReceipt:
      case InventoryMovementType.transferIn:
      case InventoryMovementType.massEntry:
      case InventoryMovementType.supplierReceipt:
      case InventoryMovementType.customerReturnMass:
      case InventoryMovementType.initialStock:
        return Colors.green.shade700;
      case InventoryMovementType.manualAdjustment:
      case InventoryMovementType.stockCorrection:
      case InventoryMovementType.massManualAdjustment:
        return Colors.blue.shade700;
      case InventoryMovementType.unknown:
      default:
        return Colors.grey.shade700;
    }
  }

  Widget _buildBottomNavItem({required BuildContext context, required IconData icon, required String label, required int itemIndex}) {
    final Color color = Colors.grey.shade600;
    return Expanded(
      child: InkWell(
        onTap: () {
          switch (itemIndex) {
            case 0:
              Routes.replaceWith(context, Routes.scanner);
              break;
            case 1:
              Routes.replaceWith(context, Routes.order);
              break;
          }
        },
        borderRadius: BorderRadius.circular(4.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPressed;
  final ThemeData theme;
  final Color color;

  const _OperationButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.onPressed,
    required this.theme,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        splashColor: color.withOpacity(0.3),
        highlightColor: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 140),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.85), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.85),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvancedOperationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPressed;
  final ThemeData theme;
  final Color color;

  const _AdvancedOperationButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.onPressed,
    required this.theme,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        splashColor: color.withOpacity(0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}