// lib/screens/product_catalog_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../models/inventory_movement.dart';
import '../models/label_print_item.dart';
import '../providers/catalog_notifier.dart';
import '../providers/catalog_state.dart';
import '../providers/app_state_notifier.dart';
import '../providers/label_notifier.dart';
import '../widgets/app_header.dart';
import '../widgets/catalog/product_catalog_card.dart';
import '../widgets/catalog/product_filter_chip.dart';
import '../widgets/catalog/edit_product_categories_dialog.dart';
import '../config/routes.dart';
import './inventory_adjustment_form_screen.dart';

class CatalogScreenArguments {
  final CatalogScreenMode mode;
  final bool allowMultipleSelection;

  const CatalogScreenArguments({
    this.mode = CatalogScreenMode.browse,
    this.allowMultipleSelection = false,
  });
}

enum CatalogScreenMode {
  browse,              // Navegación libre
  selectForInventory,  // Seleccionar para ajuste
  selectForOrder,      // Seleccionar para pedido
  selectForLabels,     // Seleccionar para etiquetas
}

class ProductCatalogScreen extends ConsumerStatefulWidget {
  final CatalogScreenArguments? arguments;

  const ProductCatalogScreen({super.key, this.arguments});

  @override
  ConsumerState<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends ConsumerState<ProductCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    ref.read(catalogProvider.notifier).setSearchTerm(_searchController.text);
  }

  void _onScroll() {
    // Future: Implementar paginación si es necesario
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogProvider);
    final appState = ref.watch(appStateNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppHeader(
        title: 'Catálogo de Productos',
        showBackButton: true,
        showCartButton: true,
        showSettingsButton: true,
      ),
      body: Column(
        children: [
          // Banner offline
          if (!appState.isOnline)
            Container(
              color: Colors.orange[800],
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 14),
                  SizedBox(width: 8),
                  Text(
                    'Modo sin conexión',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),

          // Búsqueda y botón de filtros
          _buildSearchBar(theme, catalogState),

          // Lista de productos
          Expanded(
            child: _buildProductList(catalogState, theme),
          ),

          // Última sincronización
          if (catalogState.lastSyncTimestamp != null)
            _buildLastSyncInfo(catalogState),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _syncCatalog(),
        icon: const Icon(Icons.sync),
        label: const Text('SINCRONIZAR'),
        backgroundColor: Colors.indigo[700],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, CatalogState state) {
    // Contar filtros activos
    final activeFiltersCount = state.filters.selectedCategories.length +
        (state.filters.showInStock ? 1 : 0) +
        (state.filters.showOutOfStock ? 1 : 0) +
        (state.filters.showOnBackorder ? 1 : 0);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Campo de búsqueda
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, SKU o código...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Botón de filtros
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: activeFiltersCount > 0 ? Colors.blue[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.filter_list,
                    color: activeFiltersCount > 0 ? Colors.white : Colors.grey[700],
                  ),
                  onPressed: () => _showFiltersDialog(state),
                  tooltip: 'Filtros',
                ),
              ),
              if (activeFiltersCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red[700],
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '$activeFiltersCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFiltersDialog(CatalogState state) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
              maxWidth: 400,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header con título y botón cerrar
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue[700],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_list,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Filtrar Productos',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // Contenido con scroll
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // CATEGORÍAS
                        Row(
                          children: [
                            Icon(Icons.category_outlined, color: Colors.blue[700], size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Categorías',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (state.categories.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No hay categorías disponibles',
                              style: TextStyle(color: Colors.grey[600], fontSize: 14),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: state.categories.map((category) {
                              final isSelected = state.filters.selectedCategories.contains(category);
                              return ProductFilterChip(
                                label: category,
                                isSelected: isSelected,
                                icon: Icons.category_outlined,
                                selectedColor: Colors.blue[700]!,
                                onTap: () {
                                  ref.read(catalogProvider.notifier).toggleCategoryFilter(category);
                                  // Cerrar el diálogo después de seleccionar
                                  Navigator.pop(context);
                                },
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        // ESTADO DE STOCK
                        Row(
                          children: [
                            Icon(Icons.inventory_2_outlined, color: Colors.green[700], size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Estado de Stock',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ProductFilterChip(
                              label: 'En Stock',
                              isSelected: state.filters.showInStock,
                              icon: Icons.check_circle_outline,
                              selectedColor: Colors.green[700]!,
                              onTap: () {
                                ref.read(catalogProvider.notifier).toggleStockFilter('instock');
                              },
                            ),
                            ProductFilterChip(
                              label: 'Agotado',
                              isSelected: state.filters.showOutOfStock,
                              icon: Icons.cancel_outlined,
                              selectedColor: Colors.red[700]!,
                              onTap: () {
                                ref.read(catalogProvider.notifier).toggleStockFilter('outofstock');
                              },
                            ),
                            ProductFilterChip(
                              label: 'Bajo Pedido',
                              isSelected: state.filters.showOnBackorder,
                              icon: Icons.schedule_outlined,
                              selectedColor: Colors.orange[700]!,
                              onTap: () {
                                ref.read(catalogProvider.notifier).toggleStockFilter('onbackorder');
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductList(CatalogState state, ThemeData theme) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(
                state.errorMessage!,
                style: TextStyle(color: Colors.red[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.read(catalogProvider.notifier).loadCatalog(refresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              state.searchTerm.isNotEmpty
                  ? 'No se encontraron productos'
                  : 'No hay productos en el catálogo',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            if (state.searchTerm.isEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _syncCatalog(),
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar desde WooCommerce'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(catalogProvider.notifier).loadCatalog(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: state.filteredProducts.length,
        itemBuilder: (context, index) {
          final product = state.filteredProducts[index];
          final variations = state.variationsByParent[product.id] ?? [];
          final isExpanded = state.expandedParentIds.contains(product.id);

          return ProductCatalogCard(
            key: ValueKey('product_${product.id}'),
            product: product,
            variations: variations,
            isExpanded: isExpanded,
            onToggleExpanded: () {
              ref.read(catalogProvider.notifier).toggleParentExpansion(product.id);
            },
            onTap: () => _navigateToDetail(product),
            onAdjustInventory: () => _navigateToInventoryAdjustment(product),
            onAddToOrder: () => _addToOrder(product),
            onPrintLabel: () => _addToLabelQueue(product),
            onEditCategories: () => _editProductCategories(product, state.categories),
          );
        },
      ),
    );
  }

  Widget _buildLastSyncInfo(CatalogState state) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'es_CR');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sync, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            'Última sincronización: ${dateFormat.format(state.lastSyncTimestamp!)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Future<void> _syncCatalog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Sincronizando catálogo...'),
          ],
        ),
      ),
    );

    try {
      await ref.read(catalogProvider.notifier).syncFromWooCommerce();

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Catálogo sincronizado exitosamente'),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  void _navigateToDetail(Product product) {
    Routes.navigateTo(
      context,
      Routes.productDetail,
      arguments: product.id,
    );
  }

  void _navigateToInventoryAdjustment(Product product) {
    Navigator.pushNamed(
      context,
      Routes.inventoryAdjustmentForm,
      arguments: InventoryAdjustmentFormScreenArguments(
        operationType: 'entry',
        initialProduct: product,
      ),
    );
  }

  void _addToOrder(Product product) {
    // TODO: Integrar con OrderNotifier cuando esté disponible
    // ref.read(currentOrderProvider.notifier).addProduct(product);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ ${product.name} agregado al pedido'),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  void _addToLabelQueue(Product product) {
    try {
      final labelItem = LabelPrintItem(
        productId: product.id,
        quantity: 1,
        selectedVariants: const {},
        barcode: product.barcode,
        cachedProductName: product.name,
        cachedSku: product.sku,
      );

      ref.read(labelProvider.notifier).addOrUpdateItem(labelItem);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${product.name} agregado a cola de impresión'),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _editProductCategories(Product product, List<String> availableCategories) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditProductCategoriesDialog(
        product: product,
        allAvailableCategories: availableCategories,
      ),
    );

    // Si se guardaron cambios, recargar el catálogo
    if (result == true && mounted) {
      await ref.read(catalogProvider.notifier).loadCatalog(refresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Categorías actualizadas para ${product.name}'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
