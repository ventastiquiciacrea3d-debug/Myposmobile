import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QuantitySelector extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int minValue;
  final int maxValue;

  const QuantitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.minValue = 0,
    required this.maxValue,
  });

  @override
  _QuantitySelectorState createState() => _QuantitySelectorState();
}

class _QuantitySelectorState extends State<QuantitySelector> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _parseAndSubmitText();
      }
    });

    _controller.addListener(() {
      final textValue = _controller.text;
      final int? parsedValue = int.tryParse(textValue);
      // Solo resetear si está vacío y no está en foco activo de edición
      if (parsedValue == null && textValue.isEmpty && !_focusNode.hasFocus) {
        _controller.text = widget.minValue.toString();
      }
    });
  }

  @override
  void didUpdateWidget(QuantitySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      // Evitar sobrescribir si el usuario está escribiendo activamente
      if (!_focusNode.hasFocus) {
        final textValue = _controller.text;
        final int? parsedValue = int.tryParse(textValue);
        if (parsedValue != widget.value) {
          _controller.text = widget.value.toString();
          _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length));
        }
      }
    }
  }

  void _parseAndSubmitText() {
    final textValue = _controller.text;
    int newValue = int.tryParse(textValue) ?? widget.minValue;
    _updateValue(newValue);
  }

  void _updateValue(int newValue) {
    // Si maxValue es <= 0, asumimos sin límite superior práctico (ej. 99999)
    final effectiveMaxValue = (widget.maxValue <= 0) ? 999999 : widget.maxValue;

    // Permitir minValue, asegurar que no baje de ahí
    final clampedValue = newValue.clamp(widget.minValue, effectiveMaxValue);

    if (clampedValue != widget.value) {
      widget.onChanged(clampedValue);
    }

    // Actualizar el texto si difiere y no tenemos el foco (para no interrumpir escritura)
    if (_controller.text != clampedValue.toString() && !_focusNode.hasFocus) {
      _controller.text = clampedValue.toString();
      _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool canDecrement = widget.value > widget.minValue;
    // Si maxValue es 0 o menor, asumimos infinito, así que siempre puede incrementar
    final bool canIncrement = widget.maxValue <= 0 || widget.value < widget.maxValue;

    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton(
              context: context,
              icon: Icons.remove,
              onPressed: canDecrement
                  ? () {
                _focusNode.unfocus();
                _updateValue(widget.value - 1);
              }
                  : null,
              theme: theme,
              isLeft: true,
            ),
            VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.grey.shade300,
                indent: 4,
                endIndent: 4),

            // 🛠️ FIX: Usar Flexible para evitar overflow en pantallas pequeñas
            Flexible(
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 40,
                  maxWidth: 80, // Límite ancho para que no crezca infinito
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                    EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  ),
                  onSubmitted: (_) => _parseAndSubmitText(),
                ),
              ),
            ),

            VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.grey.shade300,
                indent: 4,
                endIndent: 4),
            _buildButton(
              context: context,
              icon: Icons.add,
              onPressed: canIncrement
                  ? () {
                _focusNode.unfocus();
                _updateValue(widget.value + 1);
              }
                  : null,
              theme: theme,
              isLeft: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback? onPressed,
    required ThemeData theme,
    required bool isLeft,
  }) {
    return SizedBox(
      width: 42,
      height: double.infinity,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
              borderRadius: isLeft
                  ? const BorderRadius.only(
                  topLeft: Radius.circular(7), bottomLeft: Radius.circular(7))
                  : const BorderRadius.only(
                  topRight: Radius.circular(7),
                  bottomRight: Radius.circular(7))),
          foregroundColor:
          onPressed != null ? theme.textTheme.bodyLarge?.color : Colors.grey,
        ),
        onPressed: onPressed,
        child: Icon(icon, size: 20),
      ),
    );
  }
}