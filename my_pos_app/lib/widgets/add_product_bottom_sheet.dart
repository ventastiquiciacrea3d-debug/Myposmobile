// lib/widgets/add_product_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';

class AddProductBottomSheet extends StatefulWidget {
  final Product product;
  final Function(Product product, int quantity, Map<String, String> selectedAttributes)? onAdd;

  const AddProductBottomSheet({
    Key? key,
    required this.product,
    this.onAdd,
  }) : super(key: key);

  @override
  State<AddProductBottomSheet> createState() => _AddProductBottomSheetState();
}

class _AddProductBottomSheetState extends State<AddProductBottomSheet> {
  int _quantity = 1;
  Map<String, String> _selectedAttributes = {};
  double _currentPrice = 0.0;
  int _currentStock = 0;

  @override
  void initState() {
    super.initState();
    _currentPrice = widget.product.price;
    _currentStock = widget.product.stockQuantity ?? 0;

    // Inicializar atributos con primera opción disponible con stock
    if (widget.product.type == 'variable' &&
        widget.product.fullAttributesWithOptions != null) {
      _initializeDefaultAttributes();
    }
  }

  void _initializeDefaultAttributes() {
    final attributes = widget.product.fullAttributesWithOptions!;

    for (var entry in attributes.entries) {
      final attributeName = entry.key;
      final options = entry.value as List<dynamic>;

      if (options.isNotEmpty) {
        // Buscar primera opción con stock
        for (var option in options) {
          final variation = _findVariationByAttribute(attributeName, option.toString());
          if (variation != null && (variation['stock_quantity'] ?? 0) > 0) {
            _selectedAttributes[attributeName] = option.toString();
            break;
          }
        }

        // Si no hay stock, usar primera opción de todas formas
        if (!_selectedAttributes.containsKey(attributeName)) {
          _selectedAttributes[attributeName] = options.first.toString();
        }
      }
    }

    _updatePriceAndStock();
  }

  Map<String, dynamic>? _findVariationByAttribute(String attrName, String attrValue) {
    if (widget.product.variations == null) return null;

    for (var variation in widget.product.variations!) {
      final attrs = variation['attributes'] as List<dynamic>?;
      if (attrs == null) continue;

      for (var attr in attrs) {
        if (attr['name'] == attrName && attr['option'] == attrValue) {
          return variation;
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _findMatchingVariation() {
    if (widget.product.variations == null || _selectedAttributes.isEmpty) {
      return null;
    }

    for (var variation in widget.product.variations!) {
      final varAttrs = variation['attributes'] as List<dynamic>?;
      if (varAttrs == null) continue;

      bool allMatch = true;
      for (var entry in _selectedAttributes.entries) {
        bool found = false;
        for (var attr in varAttrs) {
          if (attr['name'] == entry.key && attr['option'] == entry.value) {
            found = true;
            break;
          }
        }
        if (!found) {
          allMatch = false;
          break;
        }
      }

      if (allMatch) {
        return variation;
      }
    }
    return null;
  }

  void _updatePriceAndStock() {
    if (widget.product.type == 'variable') {
      final variation = _findMatchingVariation();
      if (variation != null) {
        setState(() {
          _currentPrice = double.tryParse(variation['price']?.toString() ?? '0') ?? 0.0;
          _currentStock = variation['stock_quantity'] ?? 0;
        });
      }
    } else {
      setState(() {
        _currentPrice = widget.product.price;
        _currentStock = widget.product.stockQuantity ?? 0;
      });
    }
  }

  void _onAttributeChanged(String attributeName, String value) {
    setState(() {
      _selectedAttributes[attributeName] = value;
      _updatePriceAndStock();
    });
  }

  void _incrementQuantity() {
    if (_quantity < _currentStock) {
      setState(() => _quantity++);
    }
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() => _quantity--);
    }
  }

  bool _hasStock() => _currentStock > 0;

  double _getTotal() => _currentPrice * _quantity;

  List<String> _getAvailableOptions(String attributeName) {
    if (widget.product.fullAttributesWithOptions == null) return [];

    final options = widget.product.fullAttributesWithOptions![attributeName] as List<dynamic>?;
    if (options == null) return [];

    // Filtrar solo opciones con stock
    final availableOptions = <String>[];
    for (var option in options) {
      final optionStr = option.toString();

      // Crear atributos temporales para buscar variación
      final tempAttrs = Map<String, String>.from(_selectedAttributes);
      tempAttrs[attributeName] = optionStr;

      // Buscar si existe variación con stock para esta opción
      bool hasStock = false;
      if (widget.product.variations != null) {
        for (var variation in widget.product.variations!) {
          final varAttrs = variation['attributes'] as List<dynamic>?;
          if (varAttrs == null) continue;

          bool matches = true;
          for (var entry in tempAttrs.entries) {
            bool found = false;
            for (var attr in varAttrs) {
              if (attr['name'] == entry.key && attr['option'] == entry.value) {
                found = true;
                break;
              }
            }
            if (!found) {
              matches = false;
              break;
            }
          }

          if (matches && (variation['stock_quantity'] ?? 0) > 0) {
            hasStock = true;
            break;
          }
        }
      }

      if (hasStock) {
        availableOptions.add(optionStr);
      }
    }

    return availableOptions;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₡', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con imagen y nombre
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Imagen del producto
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade200,
                ),
                child: widget.product.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          widget.product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                        ),
                      )
                    : const Icon(Icons.inventory_2, size: 40),
              ),
              const SizedBox(width: 16),
              // Nombre y SKU
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SKU: ${widget.product.sku}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Stock indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _hasStock() ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _hasStock()
                            ? 'Stock: $_currentStock unidades'
                            : 'Sin stock disponible',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _hasStock() ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(),

          // Selección de atributos (si es producto variable)
          if (widget.product.type == 'variable' &&
              widget.product.fullAttributesWithOptions != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Opciones:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...widget.product.fullAttributesWithOptions!.entries.map((entry) {
              final attributeName = entry.key;
              final availableOptions = _getAvailableOptions(attributeName);

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attributeName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableOptions.map((option) {
                        final isSelected = _selectedAttributes[attributeName] == option;
                        return ChoiceChip(
                          label: Text(option),
                          selected: isSelected,
                          onSelected: (_) => _onAttributeChanged(attributeName, option),
                          selectedColor: Theme.of(context).primaryColor,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
            const Divider(),
          ],

          const SizedBox(height: 12),

          // Precio y cantidad
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Precio
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Precio unitario',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    currencyFormat.format(_currentPrice),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // Selector de cantidad
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _quantity > 1 ? _decrementQuantity : null,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _quantity.toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _hasStock() && _quantity < _currentStock
                          ? _incrementQuantity
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Total
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  currencyFormat.format(_getTotal()),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Botones de acción
          Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _hasStock()
                      ? () {
                          if (widget.onAdd != null) {
                            widget.onAdd!(widget.product, _quantity, _selectedAttributes);
                          }
                          Navigator.pop(context, {
                            'product': widget.product,
                            'quantity': _quantity,
                            'attributes': _selectedAttributes,
                            'price': _currentPrice,
                            'total': _getTotal(),
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: const Text(
                    'Agregar al Pedido',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}
