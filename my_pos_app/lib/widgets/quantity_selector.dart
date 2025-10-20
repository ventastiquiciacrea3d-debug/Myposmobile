// lib/widgets/quantity_selector.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para FilteringTextInputFormatter

class QuantitySelector extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int minValue;
  final int maxValue;

  const QuantitySelector({
    Key? key,
    required this.value,
    required this.onChanged,
    this.minValue = 0, // Valor mínimo permitido (ej. 0 para eliminar, 1 para no permitir 0)
    required this.maxValue, // Máximo valor permitido (ej. stock disponible)
  }) : super(key: key);

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

    // Listener para cuando el campo de texto pierde el foco o se presiona "Done".
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _parseAndSubmitText();
      }
    });

    // Se llama cada vez que el texto del TextField cambia.
    // Solo actualiza el controlador internamente; el onChanged del padre se llama al submit/perder foco.
    _controller.addListener(() {
      final textValue = _controller.text;
      final int? parsedValue = int.tryParse(textValue);
      if (parsedValue == null && textValue.isNotEmpty) {
        // Si el usuario borra todo y luego escribe letras o signos, resetea a 0 o minValue.
        _controller.text = widget.minValue.toString();
        _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
      }
    });
  }

  @override
  void didUpdateWidget(QuantitySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si el valor del widget (propiedad `value`) cambia desde fuera
    // (ej. OrderProvider actualiza la cantidad o se selecciona una variante)
    // y el TextField no tiene el foco (para no interrumpir la escritura del usuario)
    // O si tiene el foco pero el valor externo es definitivamente diferente al texto actual
    // (ej. el widget padre clampeó un valor y lo envió de vuelta).
    if (widget.value != oldWidget.value) {
      if (!_focusNode.hasFocus || ( _focusNode.hasFocus && _controller.text != widget.value.toString() ) ) {
        // Usar Future.microtask para evitar errores de setState durante build/layout
        Future.microtask(() {
          if (mounted) {
            _controller.text = widget.value.toString();
            // Mover el cursor al final del texto si el TextField tiene foco
            if (_focusNode.hasFocus) {
              _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
            }
          }
        });
      }
    }
  }

  // Parsea el texto del TextField, aplica las reglas y llama a onChanged del padre.
  void _parseAndSubmitText() {
    final textValue = _controller.text;
    // Si el texto está vacío, se interpreta como el valor mínimo permitido.
    int newValue = int.tryParse(textValue) ?? widget.minValue;
    _updateValue(newValue);
  }

  // Lógica centralizada para actualizar el valor, aplicando límites y notificando al padre.
  void _updateValue(int newValue) {
    // Definir un límite superior efectivo para evitar desbordamientos si maxValue es inválido
    final effectiveMaxValue = (widget.maxValue <= 0 && widget.minValue < 9999) ? 99999 : widget.maxValue;
    final clampedValue = newValue.clamp(widget.minValue, effectiveMaxValue);

    // Notificar al widget padre del cambio solo si el valor clampeado es diferente al actual.
    if (clampedValue != widget.value) {
      widget.onChanged(clampedValue);
    }

    // Asegurar que el texto del controlador siempre refleje el valor clampeado.
    if (_controller.text != clampedValue.toString()) {
      _controller.text = clampedValue.toString();
      // Mover el cursor al final, especialmente útil si el valor se clampeó
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
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
    // Determinar si los botones de incrementar/decrementar deben estar habilitados.
    final bool canDecrement = widget.value > widget.minValue;
    final bool canIncrement = widget.maxValue <= 0 || widget.value < widget.maxValue; // Si maxValue es <=0, se asume sin límite superior.

    return IntrinsicHeight( // Para que los botones y el texto tengan la misma altura.
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300), // Borde sutil.
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min, // La Row toma el mínimo espacio horizontal.
          children: [
            // Botón Decrementar.
            _buildButton(
              context: context,
              icon: Icons.remove,
              onPressed: canDecrement ? () {
                _focusNode.unfocus(); // Quitar foco del TextField antes de cambiar con botón.
                _updateValue(widget.value - 1);
              } : null, // Deshabilitado si no se puede decrementar.
              theme: theme,
              isLeft: true,
            ),
            // Separador Vertical.
            VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300, indent: 4, endIndent: 4),
            // TextField para la cantidad.
            Container(
              width: 50, // Ancho fijo para el campo de texto.
              alignment: Alignment.center,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                keyboardType: TextInputType.number, // Teclado numérico.
                inputFormatters: [FilteringTextInputFormatter.digitsOnly], // Solo permitir dígitos.
                decoration: const InputDecoration(
                  border: InputBorder.none, // Sin borde para el TextField interno.
                  isDense: true, // Hacerlo más compacto.
                  contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 4), // Ajustar padding.
                ),
                onSubmitted: (textValue) => _parseAndSubmitText(), // Cuando se presiona "done" en el teclado.
              ),
            ),
            // Separador Vertical.
            VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300, indent: 4, endIndent: 4),
            // Botón Incrementar.
            _buildButton(
              context: context,
              icon: Icons.add,
              onPressed: canIncrement ? () {
                _focusNode.unfocus(); // Quitar foco del TextField.
                _updateValue(widget.value + 1);
              } : null, // Deshabilitado si no se puede incrementar.
              theme: theme,
              isLeft: false,
            ),
          ],
        ),
      ),
    );
  }

  // Widget auxiliar para construir los botones +/-.
  Widget _buildButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback? onPressed,
    required ThemeData theme,
    required bool isLeft,
  }) {
    return SizedBox(
      width: 42, // Ancho fijo para los botones.
      height: double.infinity, // Ocupar toda la altura disponible por IntrinsicHeight.
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 40), // Tamaño mínimo del área táctil.
          padding: EdgeInsets.zero, // Sin padding interno para el TextButton.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap, // Ajustar área táctil.
          shape: RoundedRectangleBorder( // Bordes redondeados solo en los extremos.
              borderRadius: isLeft
                  ? const BorderRadius.only(topLeft: Radius.circular(7), bottomLeft: Radius.circular(7))
                  : const BorderRadius.only(topRight: Radius.circular(7), bottomRight: Radius.circular(7))
          ),
          foregroundColor: onPressed != null ? theme.textTheme.bodyLarge?.color : Colors.grey, // Color del ícono.
        ),
        onPressed: onPressed,
        child: Icon(icon, size: 20), // Tamaño del ícono.
      ),
    );
  }
}