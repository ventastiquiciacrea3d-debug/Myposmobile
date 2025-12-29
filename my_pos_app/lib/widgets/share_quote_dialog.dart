// lib/widgets/share_quote_dialog.dart
import 'package:flutter/material.dart';
import '../services/quote_share_service.dart';

/// Diálogo para compartir cotización con múltiples opciones
Future<void> showShareQuoteDialog({
  required BuildContext context,
  required List<QuoteItem> items,
  required double subtotal,
  required double taxAmount,
  required double total,
  required QuoteShareService quoteShareService,
  String? customerName,
  String? customerPhone,
  String? customerEmail,
  String? quoteNumber,
}) async {
  await showDialog(
    context: context,
    builder: (context) => _ShareQuoteDialog(
      items: items,
      subtotal: subtotal,
      taxAmount: taxAmount,
      total: total,
      quoteShareService: quoteShareService,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      quoteNumber: quoteNumber,
    ),
  );
}

class _ShareQuoteDialog extends StatefulWidget {
  final List<QuoteItem> items;
  final double subtotal;
  final double taxAmount;
  final double total;
  final QuoteShareService quoteShareService;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? quoteNumber;

  const _ShareQuoteDialog({
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.quoteShareService,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.quoteNumber,
  });

  @override
  State<_ShareQuoteDialog> createState() => _ShareQuoteDialogState();
}

class _ShareQuoteDialogState extends State<_ShareQuoteDialog> {
  final TextEditingController _notesController = TextEditingController();
  bool _isSharing = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _share(ShareMethod method) async {
    setState(() => _isSharing = true);

    try {
      final notes = _notesController.text.trim();

      switch (method) {
        case ShareMethod.whatsapp:
          await widget.quoteShareService.shareViaWhatsApp(
            items: widget.items,
            subtotal: widget.subtotal,
            taxAmount: widget.taxAmount,
            total: widget.total,
            quoteNumber: widget.quoteNumber ?? '',
            customerName: widget.customerName,
            customerPhone: widget.customerPhone,
            customerEmail: widget.customerEmail,
            notes: notes.isEmpty ? null : notes,
          );
          break;

        case ShareMethod.email:
          await widget.quoteShareService.shareViaEmail(
            items: widget.items,
            subtotal: widget.subtotal,
            taxAmount: widget.taxAmount,
            total: widget.total,
            quoteNumber: widget.quoteNumber ?? '',
            customerName: widget.customerName,
            customerPhone: widget.customerPhone,
            customerEmail: widget.customerEmail,
            notes: notes.isEmpty ? null : notes,
          );
          break;

        case ShareMethod.other:
          await widget.quoteShareService.shareGeneric(
            items: widget.items,
            subtotal: widget.subtotal,
            taxAmount: widget.taxAmount,
            total: widget.total,
            quoteNumber: widget.quoteNumber ?? '',
            customerName: widget.customerName,
            customerPhone: widget.customerPhone,
            customerEmail: widget.customerEmail,
            notes: notes.isEmpty ? null : notes,
          );
          break;

        case ShareMethod.textOnly:
          await widget.quoteShareService.shareTextOnly(
            items: widget.items,
            subtotal: widget.subtotal,
            taxAmount: widget.taxAmount,
            total: widget.total,
            quoteNumber: widget.quoteNumber ?? '',
            customerName: widget.customerName,
            notes: notes.isEmpty ? null : notes,
          );
          break;
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cotización compartida exitosamente'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al compartir: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Título
              Row(
                children: [
                  Icon(Icons.share, color: theme.primaryColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Compartir Cotización',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSharing ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Información del cliente
              if (widget.customerName != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cliente',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.customerName!,
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (widget.customerPhone != null)
                        Text(
                          widget.customerPhone!,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      if (widget.customerEmail != null)
                        Text(
                          widget.customerEmail!,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Resumen
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryRow('Productos:', '${widget.items.length}'),
                    _buildSummaryRow('Subtotal:', _formatCurrency(widget.subtotal)),
                    _buildSummaryRow('IVA (13%):', _formatCurrency(widget.taxAmount)),
                    const Divider(height: 16),
                    _buildSummaryRow(
                      'TOTAL:',
                      _formatCurrency(widget.total),
                      isBold: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Notas adicionales
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notas adicionales (opcional)',
                  hintText: 'Ej: Entrega en 3 días hábiles',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.note_alt_outlined),
                ),
                maxLines: 3,
                enabled: !_isSharing,
              ),

              const SizedBox(height: 20),

              // Botones de compartir
              Text(
                'Selecciona cómo compartir:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),

              const SizedBox(height: 12),

              // WhatsApp
              _buildShareButton(
                icon: Icons.phone,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onPressed: () => _share(ShareMethod.whatsapp),
              ),

              const SizedBox(height: 10),

              // Email
              _buildShareButton(
                icon: Icons.email,
                label: 'Email',
                color: Colors.blue.shade600,
                onPressed: () => _share(ShareMethod.email),
              ),

              const SizedBox(height: 10),

              // Otro
              _buildShareButton(
                icon: Icons.share,
                label: 'Otros',
                color: Colors.grey.shade700,
                onPressed: () => _share(ShareMethod.other),
              ),

              const SizedBox(height: 10),

              // Solo texto
              _buildShareButton(
                icon: Icons.text_fields,
                label: 'Solo Texto (sin PDF)',
                color: Colors.orange.shade700,
                onPressed: () => _share(ShareMethod.textOnly),
              ),

              if (_isSharing) ...[
                const SizedBox(height: 16),
                const Center(
                  child: CircularProgressIndicator(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 22),
      label: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 2,
      ),
      onPressed: _isSharing ? null : onPressed,
    );
  }

  String _formatCurrency(double amount) {
    return '₡${amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}';
  }
}

enum ShareMethod {
  whatsapp,
  email,
  other,
  textOnly,
}
