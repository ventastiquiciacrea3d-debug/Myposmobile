// lib/widgets/customer_selection_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/woocommerce_service.dart';
import '../locator.dart';

class CustomerSelectionDialog extends StatefulWidget {
  final Customer? selectedCustomer;

  const CustomerSelectionDialog({
    Key? key,
    this.selectedCustomer,
  }) : super(key: key);

  @override
  State<CustomerSelectionDialog> createState() => _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends State<CustomerSelectionDialog> {
  final _searchController = TextEditingController();
  final _wooService = getIt<WooCommerceService>();

  List<Customer> _customers = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadRecentCustomers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentCustomers() async {
    setState(() => _isLoading = true);

    try {
      final customersData = await _wooService.getRecentCustomers(limit: 10);
      setState(() {
        _customers = customersData.map((data) => Customer.fromJson(data)).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('[CustomerSelection] Error loading customers: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isEmpty) {
        _loadRecentCustomers();
      } else {
        _searchCustomers(query);
      }
    });
  }

  Future<void> _searchCustomers(String query) async {
    setState(() => _isLoading = true);

    try {
      final customersData = await _wooService.searchCustomers(query);
      setState(() {
        _customers = customersData.map((data) => Customer.fromJson(data)).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('[CustomerSelection] Error searching customers: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_search, color: Colors.white),
                      const SizedBox(width: 12),
                      const Text(
                        'Seleccionar Cliente',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o email...',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _loadRecentCustomers();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cliente General
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade300,
                child: const Icon(Icons.person_outline),
              ),
              title: const Text('Cliente General'),
              subtitle: const Text('Cliente sin registro'),
              trailing: widget.selectedCustomer?.id == 0
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(context, Customer(
                  id: 0,
                  email: '',
                  firstName: 'Cliente',
                  lastName: 'General',
                ));
              },
            ),

            const Divider(),

            // Lista de clientes
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.search_off, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No se encontraron clientes'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _customers.length,
                          itemBuilder: (context, index) {
                            final customer = _customers[index];
                            final isSelected = widget.selectedCustomer?.id == customer.id;

                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  customer.firstName.isNotEmpty
                                      ? customer.firstName[0].toUpperCase()
                                      : 'C',
                                ),
                              ),
                              title: Text(customer.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (customer.email.isNotEmpty)
                                    Text(customer.email),
                                  if (customer.phone != null && customer.phone!.isNotEmpty)
                                    Text(customer.phone!),
                                ],
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : null,
                              onTap: () => Navigator.pop(context, customer),
                            );
                          },
                        ),
            ),

            // Botón nuevo cliente
            Container(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('Crear Nuevo Cliente'),
                onPressed: () {
                  // TODO: Implementar creación de cliente
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Funcionalidad próximamente'),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
