// lib/widgets/variation_selector_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart' as app_product;
import '../services/local_search_service.dart';
import '../repositories/product_repository.dart';
import '../locator.dart';

/// ✅ VARIATION SELECTOR WIDGET - SOLO LOCAL
///
/// Selector de variaciones que NUNCA consulta la API.
/// SOLO muestra variaciones sincronizadas en ObjectBox.
///
/// Según especificación V3:
/// - Variaciones: 🔵 SOLO LOCAL - Solo atributos disponibles
///
/// Si no hay variaciones sincronizadas, muestra mensaje al usuario
/// para que sincronice el catálogo.
class VariationSelectorWidget extends ConsumerStatefulWidget {
  final String productId;
  final Function(app_product.Product variation)? onVariationSelected;

  const VariationSelectorWidget({
    super.key,
    required this.productId,
    this.onVariationSelected,
  });

  @override
  ConsumerState<VariationSelectorWidget> createState() =>
      _VariationSelectorWidgetState();
}

class _VariationSelectorWidgetState
    extends ConsumerState<VariationSelectorWidget> {
  final ProductRepository _productRepository = getIt<ProductRepository>();

  bool _isLoading = true;
  String? _errorMessage;
  app_product.Product? _parentProduct;
  List<app_product.Product> _variations = [];

  @override
  void initState() {
    super.initState();
    _loadVariations();
  }

  /// Cargar variaciones SOLO desde ObjectBox (local)
  Future<void> _loadVariations() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ✅ PASO 1: Obtener producto padre (SOLO LOCAL)
      final parentProduct = await _productRepository.getProductById(
        widget.productId,
        forceApi: false, // ← SOLO LOCAL
      );

      if (!mounted) return;

      if (parentProduct == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Producto no encontrado en local.\n\n"
              "Ve a Configuración → Sincronizar catálogo.";
        });
        return;
      }

      if (!parentProduct.isVariable) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Este producto no tiene variaciones.";
        });
        return;
      }

      // ✅ PASO 2: Obtener variaciones (SOLO LOCAL)
      final variations = await _productRepository.getAllVariations(
        widget.productId,
        forceApi: false, // ← SOLO LOCAL
      );

      if (!mounted) return;

      if (variations.isEmpty) {
        setState(() {
          _parentProduct = parentProduct;
          _variations = [];
          _isLoading = false;
          _errorMessage =
              "No hay variaciones sincronizadas para '${parentProduct.name}'.\n\n"
              "Ve a Configuración → Sincronizar catálogo para descargar variaciones.";
        });
        return;
      }

      // ✅ PASO 3: Mostrar variaciones disponibles
      setState(() {
        _parentProduct = parentProduct;
        _variations = variations;
        _isLoading = false;
        _errorMessage = null;
      });

      debugPrint(
          "[VariationSelector] ✅ ${variations.length} variaciones cargadas DESDE LOCAL");
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = "Error cargando variaciones: ${e.toString()}";
      });

      debugPrint("[VariationSelector] ❌ Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Cargando variaciones desde local..."),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 64,
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                label: const Text("Cerrar"),
              ),
            ],
          ),
        ),
      );
    }

    if (_variations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                "No hay variaciones disponibles para\n'${_parentProduct?.name ?? 'este producto'}'",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ Mostrar lista de variaciones
    return ListView.builder(
      itemCount: _variations.length,
      itemBuilder: (context, index) {
        final variation = _variations[index];
        return _VariationListTile(
          variation: variation,
          onTap: () {
            if (widget.onVariationSelected != null) {
              widget.onVariationSelected!(variation);
            }
            Navigator.of(context).pop(variation);
          },
        );
      },
    );
  }
}

/// Widget individual para cada variación en la lista
class _VariationListTile extends StatelessWidget {
  final app_product.Product variation;
  final VoidCallback onTap;

  const _VariationListTile({
    required this.variation,
    required this.onTap,
  });

  String _getVariationDisplayName() {
    if (variation.attributes.isEmpty) {
      return variation.name;
    }

    final attributeNames = variation.attributes
        .map((attr) => "${attr.name}: ${attr.option}")
        .join(", ");

    return attributeNames.isNotEmpty ? attributeNames : variation.name;
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _getVariationDisplayName();
    final isAvailable = variation.isAvailable;
    final stockQuantity = variation.stockQuantity ?? 0;
    final price = variation.price;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        enabled: isAvailable,
        onTap: isAvailable ? onTap : null,
        leading: CircleAvatar(
          backgroundColor: isAvailable ? Colors.green : Colors.red,
          child: Icon(
            isAvailable ? Icons.check : Icons.close,
            color: Colors.white,
          ),
        ),
        title: Text(
          displayName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isAvailable ? Colors.black : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (variation.sku.isNotEmpty)
              Text(
                "SKU: ${variation.sku}",
                style: const TextStyle(fontSize: 12),
              ),
            Text(
              isAvailable
                  ? "Stock: $stockQuantity unidades"
                  : "Agotado",
              style: TextStyle(
                fontSize: 12,
                color: isAvailable ? Colors.green[700] : Colors.red[700],
              ),
            ),
          ],
        ),
        trailing: Text(
          "₡${price.toStringAsFixed(2)}",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isAvailable ? Colors.black : Colors.grey,
          ),
        ),
      ),
    );
  }
}

/// Método helper para mostrar el selector como BottomSheet
Future<app_product.Product?> showVariationSelector({
  required BuildContext context,
  required String productId,
}) {
  return showModalBottomSheet<app_product.Product>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Selecciona una variación",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: VariationSelectorWidget(productId: productId),
          ),
        ],
      ),
    ),
  );
}
