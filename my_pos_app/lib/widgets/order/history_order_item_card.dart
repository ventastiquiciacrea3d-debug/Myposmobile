// lib/widgets/order/history_order_item_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart'; // Para acciones deslizables
import '../../models/order.dart' show Order; // Modelo del pedido

class HistoryOrderItemCard extends StatefulWidget {
  final Order order;
  final NumberFormat currencyFormat;
  final DateFormat dateTimeFormat; // Formato para fecha y hora
  // Callbacks para acciones
  final VoidCallback onEdit;
  final VoidCallback onPdf;
  final VoidCallback onMore; // Para el modal de "Más Opciones"
  final bool isExpanded; // Estado de expansión (controlado por la pantalla padre)
  final Function(bool) onExpansionChanged; // Callback cuando cambia la expansión
  // Constructores de UI para el estado del pedido
  final String Function(String) statusTextBuilder;
  final Color Function(String) statusColorBuilder;
  final IconData Function(String) statusIconBuilder;
  final SlidableController? slidableController; // Controlador para el Slidable
  final VoidCallback? onChangeStatusAction; // Acción para cambiar estado desde Slidable

  const HistoryOrderItemCard({
    Key? key,
    required this.order,
    required this.currencyFormat,
    required this.dateTimeFormat,
    required this.onEdit,
    required this.onPdf,
    required this.onMore,
    required this.isExpanded,
    required this.onExpansionChanged,
    required this.statusTextBuilder,
    required this.statusColorBuilder,
    required this.statusIconBuilder,
    this.slidableController,
    this.onChangeStatusAction,
  }) : super(key: key);

  @override
  _HistoryOrderItemCardState createState() => _HistoryOrderItemCardState();
}

class _HistoryOrderItemCardState extends State<HistoryOrderItemCard> {
  // Estado interno para controlar si se muestran todos los ítems cuando está expandido
  bool _showAllItemsInternal = false;

  @override
  void initState() {
    super.initState();
    _showAllItemsInternal = false; // Por defecto, no mostrar todos los ítems
  }

  @override
  void didUpdateWidget(HistoryOrderItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si el widget padre colapsa la tarjeta, resetear _showAllItemsInternal
    if (!widget.isExpanded && oldWidget.isExpanded) {
      if (mounted) {
        setState(() {
          _showAllItemsInternal = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Formatear ID del pedido para mostrar
    final String displayOrderId = widget.order.number ??
        (widget.order.id != null && widget.order.id!.length > 6
            ? widget.order.id!.substring(0, 6)
            : widget.order.id ?? "N/A");
    // Obtener información de display para el estado del pedido
    final statusKey = widget.order.status.toLowerCase();
    final statusText = widget.statusTextBuilder(statusKey);
    final statusColor = widget.statusColorBuilder(statusKey);
    final statusIcon = widget.statusIconBuilder(statusKey);

    // Determinar qué ítems mostrar (todos o un subconjunto)
    final itemsToDisplay = (widget.isExpanded && _showAllItemsInternal) || widget.order.items.length <= 3
        ? widget.order.items
        : widget.order.items.take(3).toList(); // Mostrar solo los primeros 3 si no se han expandido todos
    final bool hasMoreItemsToShowButton = widget.isExpanded && widget.order.items.length > 3 && !_showAllItemsInternal;

    return Slidable(
      key: ValueKey('slidable_order_${widget.order.id ?? widget.order.hashCode}'), // Key único
      controller: widget.slidableController, // Controlador para el Slidable
      groupTag: 'order-history-swipe', // Para que solo un Slidable esté abierto a la vez
      // Acciones que aparecen al deslizar hacia la izquierda (endActionPane)
      endActionPane: ActionPane(
        motion: const StretchMotion(), // Animación del panel de acciones
        extentRatio: 0.85, // Cuánto del ancho de la tarjeta ocupan las acciones
        children: [
          SlidableAction(
            onPressed: (ctx) {
              widget.slidableController?.close(); // Cerrar el panel de acciones
              widget.onChangeStatusAction?.call(); // Llamar al callback para cambiar estado
            },
            backgroundColor: Colors.deepPurpleAccent.shade200,
            foregroundColor: Colors.white,
            icon: Icons.published_with_changes_rounded,
            label: 'Estado',
            padding: EdgeInsets.zero, // Ajustar padding
          ),
          SlidableAction(
            onPressed: (ctx) {
              widget.onEdit(); // Llamar al callback de edición
              widget.slidableController?.close();
            },
            backgroundColor: Colors.blueAccent.shade400,
            foregroundColor: Colors.white,
            icon: Icons.edit_note_outlined,
            label: 'Editar',
            padding: EdgeInsets.zero,
          ),
          SlidableAction(
            onPressed: (ctx) {
              widget.onPdf(); // Llamar al callback de PDF
              widget.slidableController?.close();
            },
            backgroundColor: Colors.teal.shade600,
            foregroundColor: Colors.white,
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF',
            padding: EdgeInsets.zero,
          ),
          SlidableAction(
            onPressed: (ctx) {
              widget.onMore(); // Llamar al callback para "Más Opciones"
              widget.slidableController?.close();
            },
            backgroundColor: Colors.grey.shade600,
            foregroundColor: Colors.white,
            icon: Icons.more_horiz_rounded,
            label: 'Más',
            padding: EdgeInsets.zero,
            // Bordes redondeados solo en el extremo derecho para la última acción
            borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
          ),
        ],
      ),
      // Contenido principal de la tarjeta (ExpansionTile)
      child: Card(
          elevation: widget.isExpanded ? 2.5 : 1.5, // Sombra diferente si está expandido
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0), // Margen de la tarjeta
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: ValueKey("expansion_tile_${widget.order.id ?? widget.order.hashCode}_${widget.isExpanded}"), // Key para el ExpansionTile
            initiallyExpanded: widget.isExpanded, // Estado inicial de expansión
            onExpansionChanged: (expanding) { // Callback cuando cambia la expansión
              if (!expanding && mounted) { // Si se está colapsando
                setState(() {
                  _showAllItemsInternal = false; // Resetear para no mostrar todos los ítems
                });
              }
              widget.onExpansionChanged(expanding); // Notificar al widget padre
            },
            backgroundColor: widget.isExpanded ? theme.primaryColor.withOpacity(0.03) : theme.cardColor,
            collapsedBackgroundColor: theme.cardColor,
            iconColor: theme.primaryColor,
            collapsedIconColor: Colors.grey.shade600,
            // Icono a la izquierda con el estado del pedido
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(statusIcon, color: statusColor, size: 20),
            ),
            // Título principal de la tarjeta
            title: Text('Pedido #$displayOrderId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
            // Subtítulo con nombre del cliente, fecha y resumen
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.order.customerName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(widget.dateTimeFormat.format(widget.order.date), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                Row(children: [
                  Text('${widget.order.items.length} prod.', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                  Text('  •  ', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                  Text(widget.currencyFormat.format(widget.order.total), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: theme.textTheme.bodyLarge?.color)),
                ]),
              ],
            ),
            // Contenido que se muestra al expandir
            children: [
              if (widget.isExpanded) // Solo construir si está expandido
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 12, thickness: 0.5),
                      // Lista de ítems del pedido
                      ...itemsToDisplay.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Expanded(child: Text('${item.quantity}x ${item.name}', style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)), Text(widget.currencyFormat.format(item.effectiveSubtotal), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))]))).toList(),

                      // Botón para "Mostrar todos" si hay más ítems
                      if (hasMoreItemsToShowButton)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Center(
                            child: TextButton.icon(
                              icon: Icon(Icons.more_horiz, size: 20, color: theme.primaryColor),
                              label: Text('Mostrar todos (${widget.order.items.length})', style: TextStyle(fontSize: 13, color: theme.primaryColor)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal:10, vertical: 4),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap, // Área táctil más pequeña
                              ),
                              onPressed: () {
                                if(mounted) {
                                  setState(() {
                                    _showAllItemsInternal = true; // Mostrar todos los ítems
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      const Divider(height: 16, thickness: 0.5),
                      // Resumen de totales
                      Text('Subtotal (Base): ${widget.currencyFormat.format(widget.order.subtotal)}', style: const TextStyle(fontSize: 13)),
                      if(widget.order.discount > 0.01) Text('Descuento Ofertas: -${widget.currencyFormat.format(widget.order.discount)}', style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                      // Sumar descuentos individuales de ítems si existen
                      if (widget.order.items.fold(0.0, (sum, item) => sum + (item.individualDiscount ?? 0.0)) > 0.01)
                        Text('Dcto. Manual Items: -${widget.currencyFormat.format(widget.order.items.fold(0.0, (sum, item) => sum + (item.individualDiscount ?? 0.0)))}', style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                      Text('Impuestos: ${widget.currencyFormat.format(widget.order.tax)}', style: const TextStyle(fontSize: 13)),
                      const Divider(height: 16, thickness: 0.5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('Total: ${widget.currencyFormat.format(widget.order.total)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 15)),
                          // Botón de "Más opciones" (tres puntos) para acceder a las acciones del Slidable
                          // si el usuario no desliza.
                          IconButton(
                            icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade700),
                            tooltip: "Más opciones",
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(), // Para quitar padding extra del IconButton
                            onPressed: () {
                              // Abrir el SlidableActionPane al tocar este botón
                              widget.slidableController?.openEndActionPane();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                )
            ],
          )
      ),
    );
  }
}
