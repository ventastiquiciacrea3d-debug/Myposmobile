// lib/screens/customer_search_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/customer_notifier.dart';
import '../widgets/app_header.dart';
import '../config/routes.dart';

/// ✓ FASE 2 RIVERPOD: Migrado a ConsumerStatefulWidget
class CustomerSearchScreen extends ConsumerStatefulWidget {
  const CustomerSearchScreen({super.key});

  @override
  ConsumerState<CustomerSearchScreen> createState() => _CustomerSearchScreenState();
}

class _CustomerSearchScreenState extends ConsumerState<CustomerSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerProvider.notifier).clearSearch();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        ref.read(customerProvider.notifier).searchCustomers(_searchController.text);
      }
    });
  }

  void _selectCustomer(Map<String, dynamic> customer) {
    Navigator.pop(context, {
      'id': customer['id'].toString(),
      'name': '${customer['first_name'] ?? ''} ${customer['last_name'] ?? ''}'.trim(),
    });
  }

  void _selectGeneralCustomer() {
    Navigator.pop(context, {'id': '0', 'name': 'Cliente General'});
  }

  Future<void> _navigateToCreateCustomer() async {
    final newCustomer = await Navigator.pushNamed(context, Routes.customerEdit);
    if (newCustomer is Map<String, dynamic> && mounted) {
      Navigator.pop(context, newCustomer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerState = ref.watch(customerProvider);

    return Scaffold(
      appBar: AppHeader(
        title: 'Seleccionar Cliente',
        showBackButton: true,
        showCartButton: false,
        showSettingsButton: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o email...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(customerProvider.notifier).clearSearch();
                  },
                )
                    : null,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: const Text('Cliente General', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: _selectGeneralCustomer,
          ),
          const Divider(height: 1),
          Expanded(
            child: customerState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : customerState.error != null && customerState.displayCustomers.isEmpty
                ? Center(child: Text(customerState.error!, style: TextStyle(color: Colors.red.shade700)))
                : customerState.displayCustomers.isEmpty && _searchController.text.isNotEmpty
                ? const Center(child: Text("No se encontraron clientes."))
                : ListView.separated(
              itemCount: customerState.displayCustomers.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final customer = customerState.displayCustomers[index];
                final fullName = '${customer['first_name'] ?? ''} ${customer['last_name'] ?? ''}'.trim();
                return ListTile(
                  leading: CircleAvatar(child: Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?')),
                  title: Text(fullName.isNotEmpty ? fullName : 'Sin Nombre'),
                  subtitle: Text(customer['email'] ?? 'Sin email'),
                  onTap: () => _selectCustomer(customer),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('NUEVO CLIENTE'),
        onPressed: _navigateToCreateCustomer,
      ),
    );
  }
}