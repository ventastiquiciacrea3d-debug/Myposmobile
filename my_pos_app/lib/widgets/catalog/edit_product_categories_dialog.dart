// lib/widgets/catalog/edit_product_categories_dialog.dart
import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/storage_service.dart';
import '../../locator.dart';

class EditProductCategoriesDialog extends StatefulWidget {
  final Product product;
  final List<String> allAvailableCategories;

  const EditProductCategoriesDialog({
    super.key,
    required this.product,
    required this.allAvailableCategories,
  });

  @override
  State<EditProductCategoriesDialog> createState() => _EditProductCategoriesDialogState();
}

class _EditProductCategoriesDialogState extends State<EditProductCategoriesDialog> {
  late List<String> _selectedCategories;
  final TextEditingController _newCategoryController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedCategories = widget.product.categoryNames != null
        ? List<String>.from(widget.product.categoryNames!)
        : [];
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _saveCategories() async {
    setState(() => _isSaving = true);

    try {
      // Actualizar producto con nuevas categorías
      final updatedProduct = widget.product.copyWith(
        categoryNames: () => _selectedCategories.isEmpty ? null : _selectedCategories,
      );

      // Guardar en ObjectBox
      await getIt<StorageService>().cacheProduct(updatedProduct);

      if (mounted) {
        Navigator.pop(context, true); // true indica que se guardaron cambios
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar categorías: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _toggleCategory(String category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
    });
  }

  void _addNewCategory() {
    final newCategory = _newCategoryController.text.trim();
    if (newCategory.isNotEmpty) {
      setState(() {
        if (!_selectedCategories.contains(newCategory)) {
          _selectedCategories.add(newCategory);
        }
        _newCategoryController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Combinar categorías existentes con las disponibles
    final allCategories = <String>{
      ...widget.allAvailableCategories,
      ..._selectedCategories,
    }.where((c) => c != 'Uncategorized').toList()..sort();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.category, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Editar Categorías',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.product.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Agregar nueva categoría
                    Card(
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.add_circle_outline, color: Colors.blue[700], size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Crear Nueva Categoría',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue[900],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _newCategoryController,
                                    decoration: InputDecoration(
                                      hintText: 'Ej: Filamentos, Resinas...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                    onSubmitted: (_) => _addNewCategory(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _addNewCategory,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[700],
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Agregar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Categorías seleccionadas
                    if (_selectedCategories.isNotEmpty) ...[
                      Text(
                        'Categorías Asignadas (${_selectedCategories.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedCategories.map((category) {
                          return Chip(
                            label: Text(category),
                            deleteIcon: const Icon(Icons.close, size: 18),
                            onDeleted: () => _toggleCategory(category),
                            backgroundColor: Colors.green[100],
                            deleteIconColor: Colors.green[700],
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Categorías disponibles
                    if (allCategories.isNotEmpty) ...[
                      Text(
                        'Categorías Disponibles',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allCategories.map((category) {
                          final isSelected = _selectedCategories.contains(category);
                          return FilterChip(
                            label: Text(category),
                            selected: isSelected,
                            onSelected: (_) => _toggleCategory(category),
                            selectedColor: Colors.green[100],
                            checkmarkColor: Colors.green[700],
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveCategories,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
