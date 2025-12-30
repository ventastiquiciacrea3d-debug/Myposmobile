// lib/screens/improved_customer_selection_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../models/customer_model.dart';
import '../services/customer_manager_service.dart';

/// Pantalla mejorada de selección de cliente
class ImprovedCustomerSelectionScreen extends StatefulWidget {
  final CustomerManagerService customerService;

  const ImprovedCustomerSelectionScreen({
    super.key,
    required this.customerService,
  });

  @override
  State<ImprovedCustomerSelectionScreen> createState() =>
      _ImprovedCustomerSelectionScreenState();
}

class _ImprovedCustomerSelectionScreenState
    extends State<ImprovedCustomerSelectionScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  late TabController _tabController;
  List<CustomerModel> _searchResults = [];
  List<CustomerModel> _recentCustomers = [];
  List<CustomerModel> _contactResults = [];
  bool _isSearching = false;
  bool _isLoadingRecents = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRecentCustomers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentCustomers() async {
    setState(() => _isLoadingRecents = true);

    try {
      final recents = await widget.customerService.getRecentCustomers();
      if (mounted) {
        setState(() {
          _recentCustomers = recents;
          _isLoadingRecents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRecents = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _contactResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;

      try {
        // Buscar en clientes (WooCommerce + Local)
        final results = await widget.customerService.searchCustomers(query);

        // Buscar en contactos si está en esa tab
        if (_tabController.index == 2) {
          final contacts =
              await widget.customerService.searchDeviceContacts(query);
          if (mounted) {
            setState(() {
              _contactResults = contacts;
            });
          }
        }

        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSearching = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error en búsqueda: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  void _onCustomerSelected(CustomerModel customer) {
    Navigator.of(context).pop(customer);
  }

  Future<void> _onCreateNewCustomer() async {
    final customer = await Navigator.push<CustomerModel>(
      context,
      MaterialPageRoute(
        builder: (context) => _CreateCustomerDialog(
          customerService: widget.customerService,
        ),
      ),
    );

    if (customer != null) {
      _onCustomerSelected(customer);
    }
  }

  Future<void> _onImportFromContact(CustomerModel contact) async {
    final imported =
        await widget.customerService.importFromDeviceContact(contact);

    if (imported != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${imported.fullName} importado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      _onCustomerSelected(imported);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar Cliente'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Clientes'),
            Tab(icon: Icon(Icons.history), text: 'Recientes'),
            Tab(icon: Icon(Icons.contacts), text: 'Contactos'),
          ],
          onTap: (index) {
            // Si cambia a tab de contactos, buscar
            if (index == 2 && _searchController.text.isNotEmpty) {
              _onSearchChanged(_searchController.text);
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          _buildSearchBar(theme),

          // Contenido de tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Clientes (WooCommerce + Local)
                _buildCustomersTab(),

                // Tab 2: Recientes
                _buildRecentsTab(),

                // Tab 3: Contactos del dispositivo
                _buildContactsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onCreateNewCustomer,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo Cliente'),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surface,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, email o teléfono...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildCustomersTab() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Escribe para buscar clientes',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron clientes',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final customer = _searchResults[index];
        return _buildCustomerTile(customer);
      },
    );
  }

  Widget _buildRecentsTab() {
    if (_isLoadingRecents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recentCustomers.isEmpty) {
      return const Center(
        child: Text(
          'No hay clientes recientes',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _recentCustomers.length,
      itemBuilder: (context, index) {
        final customer = _recentCustomers[index];
        return _buildCustomerTile(customer);
      },
    );
  }

  Widget _buildContactsTab() {
    if (_searchController.text.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Escribe para buscar en tus contactos',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_contactResults.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron contactos',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _contactResults.length,
      itemBuilder: (context, index) {
        final contact = _contactResults[index];
        return _buildContactTile(contact);
      },
    );
  }

  Widget _buildCustomerTile(CustomerModel customer) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: customer.source == CustomerSource.woocommerce
            ? Colors.blue
            : Colors.green,
        child: Text(
          customer.firstName.isNotEmpty
              ? customer.firstName[0].toUpperCase()
              : '?',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(customer.fullName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customer.email.isNotEmpty) Text(customer.email),
          if (customer.phone != null && customer.phone!.isNotEmpty)
            Text(customer.phone!),
          Text(
            customer.source.displayName,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
      trailing: customer.isSyncedWithWoo
          ? const Icon(Icons.cloud_done, color: Colors.green, size: 20)
          : const Icon(Icons.cloud_off, color: Colors.grey, size: 20),
      onTap: () => _onCustomerSelected(customer),
    );
  }

  Widget _buildContactTile(CustomerModel contact) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.orange,
        child: Icon(Icons.person, color: Colors.white),
      ),
      title: Text(contact.fullName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (contact.email.isNotEmpty) Text(contact.email),
          if (contact.phone != null && contact.phone!.isNotEmpty)
            Text(contact.phone!),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle, color: Colors.blue),
        onPressed: () => _onImportFromContact(contact),
        tooltip: 'Importar contacto',
      ),
      onTap: () => _onImportFromContact(contact),
    );
  }
}

/// Diálogo para crear nuevo cliente
class _CreateCustomerDialog extends StatefulWidget {
  final CustomerManagerService customerService;

  const _CreateCustomerDialog({required this.customerService});

  @override
  State<_CreateCustomerDialog> createState() => _CreateCustomerDialogState();
}

class _CreateCustomerDialogState extends State<_CreateCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companyController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _createCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final customer = CustomerModel(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        company: _companyController.text.trim().isNotEmpty
            ? _companyController.text.trim()
            : null,
        source: CustomerSource.manual,
        createdAt: DateTime.now(),
      );

      final created = await widget.customerService.createCustomer(customer);

      if (created != null && mounted) {
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creando cliente: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Cliente'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _firstNameController,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El nombre es requerido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lastNameController,
              decoration: const InputDecoration(
                labelText: 'Apellido *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El apellido es requerido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El email es requerido';
                }
                if (!value.contains('@')) {
                  return 'Email inválido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _companyController,
              decoration: const InputDecoration(
                labelText: 'Empresa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isCreating ? null : _createCustomer,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isCreating
                  ? const CircularProgressIndicator()
                  : const Text('CREAR CLIENTE'),
            ),
          ],
        ),
      ),
    );
  }
}
