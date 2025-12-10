// lib/screens/draft_orders_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';
import '../locator.dart';

class DraftOrdersScreen extends StatefulWidget {
  const DraftOrdersScreen({Key? key}) : super(key: key);

  @override
  State<DraftOrdersScreen> createState() => _DraftOrdersScreenState();
}

class _DraftOrdersScreenState extends State<DraftOrdersScreen> {
  final _storageService = getIt<StorageService>();
  List<Map<String, dynamic>> _drafts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    setState(() => _isLoading = true);

    try {
      final drafts = await _storageService.getAllDraftOrders();
      setState(() {
        _drafts = drafts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[DraftOrders] Error loading drafts: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar borradores')),
        );
      }
    }
  }

  Future<void> _deleteDraft(String draftId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Borrador'),
        content: const Text('¿Estás seguro de que deseas eliminar este borrador?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _storageService.deleteDraftOrder(draftId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Borrador eliminado')),
          );
        }
        _loadDrafts();
      } catch (e) {
        debugPrint('[DraftOrders] Error deleting draft: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al eliminar borrador')),
          );
        }
      }
    }
  }

  Future<void> _clearAllDrafts() async {
    if (_drafts.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Todos los Borradores'),
        content: Text(
          '¿Estás seguro de que deseas eliminar TODOS los ${_drafts.length} borradores?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar Todos'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _storageService.clearAllDraftOrders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Todos los borradores eliminados')),
          );
        }
        _loadDrafts();
      } catch (e) {
        debugPrint('[DraftOrders] Error clearing drafts: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al eliminar borradores')),
          );
        }
      }
    }
  }

  void _loadDraft(Map<String, dynamic> draft) {
    Navigator.pop(context, draft);
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Fecha desconocida';

    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) {
        return 'Hace un momento';
      } else if (difference.inHours < 1) {
        return 'Hace ${difference.inMinutes} minutos';
      } else if (difference.inDays < 1) {
        return 'Hace ${difference.inHours} horas';
      } else if (difference.inDays < 7) {
        return 'Hace ${difference.inDays} días';
      } else {
        return DateFormat('dd/MM/yyyy HH:mm').format(date);
      }
    } catch (e) {
      return 'Fecha inválida';
    }
  }

  int _getItemCount(Map<String, dynamic> draft) {
    final items = draft['items'] as List<dynamic>?;
    if (items == null) return 0;

    int totalItems = 0;
    for (var item in items) {
      totalItems += (item['quantity'] ?? 1) as int;
    }
    return totalItems;
  }

  double _getTotal(Map<String, dynamic> draft) {
    final totals = draft['totals'] as Map<String, dynamic>?;
    if (totals != null && totals['total'] != null) {
      return (totals['total'] as num).toDouble();
    }

    // Calcular del items si no hay totals
    final items = draft['items'] as List<dynamic>?;
    if (items == null) return 0.0;

    double total = 0.0;
    for (var item in items) {
      final subtotal = (item['subtotal'] ?? 0.0) as num;
      total += subtotal.toDouble();
    }
    return total;
  }

  String _getCustomerName(Map<String, dynamic> draft) {
    final customer = draft['customer'] as Map<String, dynamic>?;
    if (customer == null) return 'Cliente General';

    final firstName = customer['first_name'] ?? '';
    final lastName = customer['last_name'] ?? '';
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? 'Cliente General' : name;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₡', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Borradores de Pedidos'),
        actions: [
          if (_drafts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Eliminar todos',
              onPressed: _clearAllDrafts,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.drafts_outlined,
                        size: 80,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay borradores guardados',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Los pedidos que guardes como borrador\naparecerán aquí',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDrafts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _drafts.length,
                    itemBuilder: (context, index) {
                      final draft = _drafts[index];
                      final itemCount = _getItemCount(draft);
                      final total = _getTotal(draft);
                      final customerName = _getCustomerName(draft);
                      final createdAt = _formatDate(draft['createdAt']);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        child: InkWell(
                          onTap: () => _loadDraft(draft),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.drafts,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            customerName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            createdAt,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      color: Colors.red,
                                      onPressed: () => _deleteDraft(draft['id']),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),
                                const Divider(),
                                const SizedBox(height: 12),

                                // Información del pedido
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Productos
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.shopping_cart_outlined,
                                          size: 20,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$itemCount ${itemCount == 1 ? 'producto' : 'productos'}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Total
                                    Text(
                                      currencyFormat.format(total),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Botón cargar
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.restore),
                                    label: const Text('Cargar Borrador'),
                                    onPressed: () => _loadDraft(draft),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
