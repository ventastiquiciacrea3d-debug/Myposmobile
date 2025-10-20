// lib/screens/label_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/label_print_item.dart';
import '../providers/label_provider.dart';
import '../widgets/shared/label_preview.dart';

class LabelSettingsScreen extends StatefulWidget {
  const LabelSettingsScreen({Key? key}) : super(key: key);

  @override
  State<LabelSettingsScreen> createState() => _LabelSettingsScreenState();
}

class _LabelSettingsScreenState extends State<LabelSettingsScreen> {
  String _openPanel = 'fields';

  final List<Map<String, dynamic>> _fieldData = [
    {'key': 'productName', 'name': 'Nombre'},
    {'key': 'variants', 'name': 'Variantes'},
    {'key': 'quantity', 'name': 'Cantidad'},
    {'key': 'date', 'name': 'Fecha'},
    {'key': 'lotNumber', 'name': 'Lote'},
    {'key': 'barcode', 'name': 'Código Barras'},
    {'key': 'sku', 'name': 'SKU'},
    {'key': 'brand', 'name': 'Marca'},
  ];

  void _togglePanel(String panel) {
    setState(() {
      _openPanel = _openPanel == panel ? '' : panel;
    });
  }

  void _showFieldEditModal(BuildContext context, String fieldKey, LabelProvider provider) {
    final settings = provider.settings;
    final fieldName = _fieldData.firstWhere((f) => f['key'] == fieldKey, orElse: () => {'name': ''})['name'];
    final currentLayout = settings.fieldLayouts[fieldKey] ?? {};

    Map<String, dynamic> tempLayout = Map.from(currentLayout);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateTempLayout(Map<String, dynamic> newData) {
              setDialogState(() => tempLayout.addAll(newData));
            }

            final isTextField = fieldKey != 'barcode';

            return AlertDialog(
              title: Text('Ajustes para "$fieldName"', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              contentPadding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ModalSection(
                      title: 'Columnas en la Fila',
                      child: _OptionsToggle(
                        currentValue: tempLayout['columns'] ?? 1,
                        options: const [
                          // --- INICIO DE CORRECCIÓN ---
                          {'value': 1, 'child': Icon(LucideIcons.rectangleHorizontal)},
                          {'value': 2, 'child': Icon(LucideIcons.columns)}, // El nombre correcto es 'columns'
                          // --- FIN DE CORRECCIÓN ---
                        ],
                        onChanged: (val) => updateTempLayout({'columns': val}),
                      ),
                    ),

                    if (isTextField) ...[
                      const Divider(height: 20),
                      _ModalSection(
                        title: 'Alineación de Texto',
                        child: _OptionsToggle(
                          currentValue: tempLayout['align'] ?? 'left',
                          options: const [
                            {'value': 'left', 'child': Icon(Icons.format_align_left, size: 20)},
                            {'value': 'center', 'child': Icon(Icons.format_align_center, size: 20)},
                            {'value': 'right', 'child': Icon(Icons.format_align_right, size: 20)},
                          ],
                          onChanged: (val) => updateTempLayout({'align': val}),
                        ),
                      ),
                      const Divider(height: 20),
                      _ModalSection(
                        title: 'Tamaño de Fuente',
                        child: _OptionsToggle(
                          currentValue: tempLayout['size'] ?? 'medium',
                          options: const [
                            {'value': 'small', 'child': Text('A', style: TextStyle(fontSize: 12))},
                            {'value': 'medium', 'child': Text('A', style: TextStyle(fontSize: 16))},
                            {'value': 'large', 'child': Text('A', style: TextStyle(fontSize: 20))},
                          ],
                          onChanged: (val) => updateTempLayout({'size': val}),
                        ),
                      ),

                      const Divider(height: 20),
                      _ModalSection(
                        title: 'Grosor de Fuente',
                        child: _OptionsToggle(
                          currentValue: tempLayout['weight'] ?? 'normal',
                          options: const [
                            {'value': 'light', 'child': Text('B', style: TextStyle(fontWeight: FontWeight.w300))},
                            {'value': 'normal', 'child': Text('B', style: TextStyle(fontWeight: FontWeight.w500))},
                            {'value': 'bold', 'child': Text('B', style: TextStyle(fontWeight: FontWeight.w700))},
                          ],
                          onChanged: (val) => updateTempLayout({'weight': val}),
                        ),
                      ),

                      const Divider(height: 20),
                      _ModalSection(
                        title: 'Espaciado Vertical (x Altura)',
                        child: _OptionsToggle(
                          currentValue: (tempLayout['spacing'] as num? ?? 1.5).toDouble(),
                          options: const [
                            {'value': 1.0, 'child': Text('1.0')},
                            {'value': 1.5, 'child': Text('1.5')},
                            {'value': 2.0, 'child': Text('2.0')},
                            {'value': 2.5, 'child': Text('2.5')},
                          ],
                          onChanged: (val) => updateTempLayout({'spacing': val}),
                        ),
                      ),

                      if (fieldKey == 'productName') ...[
                        const Divider(height: 20),
                        _ModalSection(
                          title: 'Ajuste de Texto Largo',
                          child: _OptionsToggle(
                            currentValue: tempLayout['fit'] ?? 'truncate',
                            options: const [
                              {'value': 'truncate', 'child': Icon(Icons.text_fields_outlined)},
                              {'value': 'wrap', 'child': Icon(Icons.wrap_text)},
                              {'value': 'full', 'child': Icon(Icons.fit_screen_outlined)},
                            ],
                            onChanged: (val) => updateTempLayout({'fit': val}),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    provider.updateFieldLayout(fieldKey, tempLayout);
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LabelProvider>();
    final settings = provider.settings;

    final exampleData = SerializableLabelData(
      displayName: 'Producto de Ejemplo con Nombre Largo',
      displaySku: 'SKU-123-ABC',
      quantity: 1,
      selectedVariants: const {'Talla': 'M', 'Color': 'Azul'},
      brand: 'Mi Marca',
      barcode: 'SKU-123-ABC',
      lotNumber: 'LOTE-001',
      date: DateFormat('dd/MM/yy', 'es_CR').format(DateTime.now()),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        title: const Text('Ajustes de Etiqueta', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(LucideIcons.arrowLeft), onPressed: () => Navigator.of(context).pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            LabelPreview(settings: settings, data: exampleData),
            const SizedBox(height: 24),
            _buildSettingsAccordions(provider, settings),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom * 0.5),
        color: Colors.white,
        child: ElevatedButton.icon(
          icon: const Icon(LucideIcons.check, size: 20),
          label: const Text('GUARDAR Y VOLVER'),
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsAccordions(LabelProvider provider, LabelSettings settings) {
    return Column(
      children: [
        _AccordionItem(
          title: 'Campos Visibles y Orden',
          isOpen: _openPanel == 'fields',
          onToggle: () => _togglePanel('fields'),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: settings.fieldOrder.length,
            itemBuilder: (context, index) {
              final key = settings.fieldOrder[index];
              final field = _fieldData.firstWhere((f) => f['key'] == key, orElse: () => {'name': 'Desconocido'});
              return Card(
                key: ValueKey(key),
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                child: ListTile(
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(LucideIcons.gripVertical, color: Colors.grey),
                  ),
                  title: Text(field['name'] as String),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_note, size: 22),
                        tooltip: 'Editar Estilos',
                        onPressed: () => _showFieldEditModal(context, key, provider),
                      ),
                      Switch(
                        value: settings.visibleAttributes[key] ?? false,
                        onChanged: (checked) => provider.updateVisibleAttribute(key, checked),
                        activeColor: Colors.red,
                      ),
                    ],
                  ),
                ),
              );
            },
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final items = List<String>.from(settings.fieldOrder);
              final item = items.removeAt(oldIndex);
              items.insert(newIndex, item);
              provider.updateFieldOrder(items);
            },
          ),
        ),
        _AccordionItem(
          title: 'Dimensiones de Etiqueta',
          isOpen: _openPanel == 'dimensions',
          onToggle: () => _togglePanel('dimensions'),
          child: _DimensionsControl(
            settings: settings,
            onLayoutChanged: provider.updateLabelLayout,
          ),
        ),
      ],
    );
  }
}

class _ModalSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _ModalSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _OptionsToggle extends StatelessWidget {
  final dynamic currentValue;
  final List<Map<String, dynamic>> options;
  final Function(dynamic value) onChanged;

  const _OptionsToggle({
    required this.currentValue,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: options.map((option) {
          final isSelected = currentValue == option['value'];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: ElevatedButton(
                onPressed: () => onChanged(option['value']),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: isSelected ? const Color(0xFFDC2626) : Colors.white,
                  foregroundColor: isSelected ? Colors.white : const Color(0xFF374151),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: isSelected ? 2 : 0,
                ),
                child: option['child'] as Widget,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AccordionItem extends StatelessWidget {
  final String title;
  final bool isOpen;
  final VoidCallback onToggle;
  final Widget child;

  const _AccordionItem({required this.title, required this.isOpen, required this.onToggle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            onTap: onToggle,
            trailing: AnimatedRotation(
              turns: isOpen ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: const Icon(LucideIcons.chevronDown),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Container(
              width: double.infinity,
              padding: isOpen ? const EdgeInsets.all(16.0) : EdgeInsets.zero,
              decoration: BoxDecoration(border: isOpen ? Border(top: BorderSide(color: Colors.grey[200]!)) : null),
              child: isOpen ? child : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DimensionsControl extends StatefulWidget {
  final LabelSettings settings;
  final Function(double, double) onLayoutChanged;

  const _DimensionsControl({required this.settings, required this.onLayoutChanged});

  @override
  State<_DimensionsControl> createState() => _DimensionsControlState();
}

class _DimensionsControlState extends State<_DimensionsControl> {
  late TextEditingController _widthController;
  late TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: widget.settings.labelLayout['width']?.toStringAsFixed(1) ?? '50.0');
    _heightController = TextEditingController(text: widget.settings.labelLayout['height']?.toStringAsFixed(1) ?? '38.0');
  }

  @override
  void didUpdateWidget(_DimensionsControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings.labelLayout != oldWidget.settings.labelLayout) {
      _widthController.text = widget.settings.labelLayout['width']?.toStringAsFixed(1) ?? '50.0';
      _heightController.text = widget.settings.labelLayout['height']?.toStringAsFixed(1) ?? '38.0';
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _onDimensionChange() {
    final width = double.tryParse(_widthController.text) ?? 50.0;
    final height = double.tryParse(_heightController.text) ?? 38.0;
    widget.onLayoutChanged(width, height);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tamaño Físico (milímetros)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151))),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _widthController,
                decoration: const InputDecoration(labelText: 'Ancho (mm)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _onDimensionChange(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _heightController,
                decoration: const InputDecoration(labelText: 'Alto (mm)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _onDimensionChange(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}