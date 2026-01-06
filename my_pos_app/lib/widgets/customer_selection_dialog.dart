// lib/widgets/customer_selection_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/customer.dart';
import '../models/customer_model.dart';
import '../services/customer_manager_service.dart';
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

class _CustomerSelectionDialogState extends State<CustomerSelectionDialog>
    with SingleTickerProviderStateMixin {
  // Services (inyectados vía GetIt)
  late CustomerManagerService _customerService;

  // UI Controllers
  late TabController _tabController;
  final _searchController = TextEditingController();
  Timer? _debounce;

  // Data State
  List<Customer> _recentCustomers = [];
  List<Customer> _searchResults = [];
  List<Customer> _contactResults = [];

  // Loading States
  bool _isLoadingRecents = false;
  bool _isSearching = false;
  bool _isLoadingContacts = false;

  @override
  void initState() {
    super.initState();

    // Inyectar servicios
    _customerService = getIt<CustomerManagerService>();

    // Configurar TabController
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Escuchar cambios en búsqueda
    _searchController.addListener(_onSearchChanged);

    // Cargar clientes recientes (Req #1)
    _loadRecentCustomers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ============================================
  // CONVERSIÓN DE MODELOS
  // ============================================

  /// Convierte CustomerModel (SQLite) a Customer (Hive)
  Customer _convertToCustomer(CustomerModel model) {
    return Customer(
      id: model.id ?? 0,
      email: model.email,
      firstName: model.firstName,
      lastName: model.lastName,
      phone: model.phone,
      billing: (model.address != null ||
               model.city != null ||
               model.state != null ||
               model.postcode != null ||
               model.country != null)
          ? {
              if (model.phone != null) 'phone': model.phone,
              if (model.address != null) 'address_1': model.address,
              if (model.city != null) 'city': model.city,
              if (model.state != null) 'state': model.state,
              if (model.postcode != null) 'postcode': model.postcode,
              if (model.country != null) 'country': model.country,
              if (model.company != null) 'company': model.company,
            }
          : null,
      shipping: null,
    );
  }

  /// Convierte Customer (Hive) a CustomerModel (SQLite)
  CustomerModel _convertToCustomerModel(Customer customer) {
    final billing = customer.billing;
    return CustomerModel(
      id: customer.id,
      firstName: customer.firstName,
      lastName: customer.lastName,
      email: customer.email,
      phone: customer.phone ?? billing?['phone'],
      company: billing?['company'],
      address: billing?['address_1'],
      city: billing?['city'],
      state: billing?['state'],
      postcode: billing?['postcode'],
      country: billing?['country'],
      source: CustomerSource.woocommerce,
      isSyncedWithWoo: customer.id > 0,
    );
  }

  // ============================================
  // CARGA Y BÚSQUEDA DE DATOS
  // ============================================

  /// Cargar últimos 10 clientes de WooCommerce (Req #1)
  Future<void> _loadRecentCustomers() async {
    if (!mounted) return;

    setState(() => _isLoadingRecents = true);

    try {
      final recentsModels = await _customerService.getRecentCustomers(limit: 10);

      if (mounted) {
        setState(() {
          _recentCustomers = recentsModels
              .map((model) => _convertToCustomer(model))
              .toList();
          _isLoadingRecents = false;
        });
      }

      debugPrint('[CustomerSelection] ✅ Cargados ${_recentCustomers.length} clientes recientes');
    } catch (e) {
      debugPrint('[CustomerSelection] Error cargando recientes: $e');
      if (mounted) {
        setState(() => _isLoadingRecents = false);
      }
    }
  }

  /// Búsqueda de clientes en WooCommerce
  Future<void> _searchCustomers(String query) async {
    if (!mounted) return;

    setState(() => _isSearching = true);

    try {
      final resultsModels = await _customerService.searchCustomers(query);

      if (mounted) {
        setState(() {
          _searchResults = resultsModels
              .map((model) => _convertToCustomer(model))
              .toList();
          _isSearching = false;
        });
      }

      debugPrint('[CustomerSelection] Búsqueda WooCommerce: ${_searchResults.length} resultados');
    } catch (e) {
      debugPrint('[CustomerSelection] Error buscando clientes: $e');
      if (mounted) {
        setState(() => _isSearching = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error en búsqueda: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Búsqueda de contactos del dispositivo
  Future<void> _searchContacts(String query) async {
    if (!mounted) return;

    setState(() => _isLoadingContacts = true);

    try {
      final contactsModels = await _customerService.searchDeviceContacts(query);

      if (mounted) {
        setState(() {
          _contactResults = contactsModels
              .map((model) => _convertToCustomer(model))
              .toList();
          _isLoadingContacts = false;
        });
      }

      debugPrint('[CustomerSelection] Búsqueda contactos: ${_contactResults.length} resultados');
    } catch (e) {
      debugPrint('[CustomerSelection] Error buscando contactos: $e');
      if (mounted) {
        setState(() => _isLoadingContacts = false);

        // Verificar si es error de permisos
        _showPermissionDeniedSnackBar();
      }
    }
  }

  // ============================================
  // LISTENERS
  // ============================================

  /// Manejador de cambio de tab
  void _onTabChanged() {
    if (!mounted) return;

    // Limpiar búsqueda al cambiar de tab
    final query = _searchController.text.trim();

    if (query.isNotEmpty) {
      // Re-ejecutar búsqueda para el tab actual
      _onSearchChanged();
    }
  }

  /// Manejador de cambio en campo de búsqueda
  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _contactResults = [];
      });
      return;
    }

    // Debounce de 500ms
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      switch (_tabController.index) {
        case 0: // Tab Clientes (WooCommerce)
          _searchCustomers(query);
          break;
        case 1: // Tab Recientes (no tiene búsqueda)
          break;
        case 2: // Tab Contactos
          _searchContacts(query);
          break;
      }
    });
  }

  // ============================================
  // ACCIONES DE USUARIO
  // ============================================

  /// Importar contacto del dispositivo como cliente
  Future<void> _onImportContact(Customer contact) async {
    // ✅ Email es OPCIONAL - Si no tiene email, se puede importar igual
    // Solo validar si el email existe y es válido (si está presente)
    if (contact.email.isNotEmpty && !contact.email.contains('@')) {
      // Email presente pero inválido - preguntar si quiere corregirlo
      await _showAddEmailDialog(contact);
      return;
    }

    try {
      final contactModel = _convertToCustomerModel(contact);
      final imported = await _customerService.importFromDeviceContact(contactModel);

      if (imported != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${imported.fullName} importado correctamente'),
            backgroundColor: Colors.green,
          ),
        );

        // Cerrar diálogo y retornar contacto importado
        final customer = _convertToCustomer(imported);
        Navigator.pop(context, customer);
      }
    } catch (e) {
      debugPrint('[CustomerSelection] Error importando contacto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al importar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Exportar cliente a contactos del dispositivo
  Future<void> _exportToContacts(Customer customer) async {
    try {
      final customerModel = _convertToCustomerModel(customer);
      final success = await _customerService.saveToDeviceContacts(customerModel);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cliente exportado a contactos'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo exportar. Verifica los permisos.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[CustomerSelection] Error exportando a contactos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Crear nuevo cliente
  Future<void> _onCreateNewCustomer() async {
    final customer = await showDialog<Customer>(
      context: context,
      builder: (context) => _CreateCustomerDialog(
        customerService: _customerService,
      ),
    );

    if (customer != null && mounted) {
      Navigator.pop(context, customer);
    }
  }

  /// Mostrar opciones de cliente (long press)
  void _showCustomerOptions(Customer customer) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.contacts, color: Colors.blue),
              title: const Text('Exportar a Contactos'),
              onTap: () {
                Navigator.pop(context);
                _exportToContacts(customer);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancelar'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // DIÁLOGOS Y MENSAJES
  // ============================================

  /// Mostrar diálogo para agregar email a contacto
  Future<void> _showAddEmailDialog(Customer contact) async {
    final emailController = TextEditingController();

    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email Requerido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('El contacto "${contact.name}" no tiene email.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isNotEmpty && email.contains('@')) {
                Navigator.pop(context, email);
              }
            },
            child: const Text('AGREGAR'),
          ),
        ],
      ),
    );

    if (email != null && email.isNotEmpty && mounted) {
      // Crear nuevo contacto con email
      final updatedContact = Customer(
        id: contact.id,
        email: email,
        firstName: contact.firstName,
        lastName: contact.lastName,
        phone: contact.phone,
        billing: contact.billing,
        shipping: contact.shipping,
      );

      await _onImportContact(updatedContact);
    }
  }

  /// Mostrar mensaje de permisos denegados
  void _showPermissionDeniedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Permisos de contactos denegados'),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: 'CONFIGURACIÓN',
          textColor: Colors.white,
          onPressed: () => openAppSettings(),
        ),
      ),
    );
  }

  /// Obtener hint de búsqueda según tab activo
  String _getSearchHint() {
    switch (_tabController.index) {
      case 0:
        return 'Buscar por nombre o email...';
      case 1:
        return 'Clientes recientes';
      case 2:
        return 'Buscar en mis contactos...';
      default:
        return 'Buscar...';
    }
  }

  // ============================================
  // UI BUILDERS
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Cliente General (siempre visible)
            _buildGeneralCustomerTile(),

            const Divider(height: 1),

            // TabBar
            _buildTabBar(),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCustomersTab(),
                  _buildRecentsTab(),
                  _buildContactsTab(),
                ],
              ),
            ),

            // Botón Crear Cliente
            _buildCreateCustomerButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
            decoration: InputDecoration(
              hintText: _getSearchHint(),
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                          _contactResults = [];
                        });
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
    );
  }

  Widget _buildGeneralCustomerTile() {
    return ListTile(
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
        Navigator.pop(
          context,
          Customer(
            id: 0,
            email: '',
            firstName: 'Cliente',
            lastName: 'General',
          ),
        );
      },
    );
  }

  Widget _buildTabBar() {
    return Material(
      color: Colors.grey.shade100,
      child: TabBar(
        controller: _tabController,
        labelColor: Theme.of(context).primaryColor,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Theme.of(context).primaryColor,
        tabs: const [
          Tab(icon: Icon(Icons.people), text: 'Clientes'),
          Tab(icon: Icon(Icons.history), text: 'Recientes'),
          Tab(icon: Icon(Icons.contacts), text: 'Contactos'),
        ],
      ),
    );
  }

  Widget _buildCustomersTab() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Escribe para buscar clientes de WooCommerce',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No se encontraron clientes'),
          ],
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No hay clientes recientes'),
          ],
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
    if (_searchController.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Escribe para buscar en tus contactos del dispositivo',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isLoadingContacts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_contactResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.contacts_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No se encontraron contactos'),
          ],
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

  Widget _buildCustomerTile(Customer customer) {
    final isSelected = widget.selectedCustomer?.id == customer.id;
    final initial = customer.firstName.isNotEmpty
        ? customer.firstName[0].toUpperCase()
        : 'C';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: customer.id > 0 ? Colors.blue : Colors.green,
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(customer.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (customer.email.isNotEmpty) Text(customer.email),
          if (customer.phone != null && customer.phone!.isNotEmpty)
            Text(customer.phone!),
        ],
      ),
      trailing: customer.id > 0
          ? const Icon(Icons.cloud_done, color: Colors.green, size: 20)
          : (isSelected
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null),
      onTap: () => Navigator.pop(context, customer),
      onLongPress: () => _showCustomerOptions(customer),
    );
  }

  Widget _buildContactTile(Customer contact) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.orange,
        child: Icon(Icons.person, color: Colors.white),
      ),
      title: Text(contact.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contact.email.isNotEmpty) Text(contact.email),
          if (contact.phone != null && contact.phone!.isNotEmpty)
            Text(contact.phone!),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle, color: Colors.blue),
        onPressed: () => _onImportContact(contact),
        tooltip: 'Importar contacto',
      ),
      onTap: () => _onImportContact(contact),
    );
  }

  Widget _buildCreateCustomerButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        icon: const Icon(Icons.person_add),
        label: const Text('Crear Nuevo Cliente'),
        onPressed: _onCreateNewCustomer,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
  }
}

// ============================================
// DIÁLOGO CREAR NUEVO CLIENTE
// ============================================

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
  bool _saveToContacts = false;
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
      final customerModel = CustomerModel(
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

      final created = await widget.customerService.createCustomer(customerModel);

      if (created != null) {
        // Si el checkbox está marcado, guardar en contactos
        if (_saveToContacts) {
          await widget.customerService.saveToDeviceContacts(created);
        }

        if (mounted) {
          // Convertir a Customer (Hive) para retornar
          final customer = Customer(
            id: created.id ?? 0,
            email: created.email,
            firstName: created.firstName,
            lastName: created.lastName,
            phone: created.phone,
          );

          Navigator.of(context).pop(customer);
        }
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
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_add, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Nuevo Cliente',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
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
                      prefixIcon: Icon(Icons.person_outline),
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
                      prefixIcon: Icon(Icons.email_outlined),
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
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _companyController,
                    decoration: const InputDecoration(
                      labelText: 'Empresa',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _saveToContacts,
                    onChanged: (value) {
                      setState(() => _saveToContacts = value ?? false);
                    },
                    title: const Text('Guardar en mis contactos'),
                    subtitle: const Text('Agregar a contactos del dispositivo'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isCreating ? null : _createCustomer,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'CREAR CLIENTE',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
