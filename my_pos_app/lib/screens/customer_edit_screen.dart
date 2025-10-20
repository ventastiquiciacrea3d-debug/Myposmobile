// lib/screens/customer_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Para acceder a WooCommerceService
import 'package:flutter/foundation.dart'; // Para kDebugMode
import 'package:flutter/services.dart'; // Para input formatters
import 'package:flutter_contacts/flutter_contacts.dart'; // Para acceder a contactos
import 'package:permission_handler/permission_handler.dart'; // Para permisos

import '../services/woocommerce_service.dart'; // Para el servicio y excepciones
import '../widgets/app_header.dart'; // Widget de cabecera común
// import '../config/routes.dart'; // No se usa directamente para navegación desde aquí

class CustomerEditScreen extends StatefulWidget {
  const CustomerEditScreen({Key? key}) : super(key: key);

  @override
  State<CustomerEditScreen> createState() => _CustomerEditScreenState();
}

class _CustomerEditScreenState extends State<CustomerEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _saveToDeviceContacts = false; // Estado del Checkbox
  bool _isSaving = false; // Para indicar si se está guardando
  String? _saveError; // Para mostrar mensajes de error

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) { // Validar formulario
      debugPrint("_saveCustomer: Form validation failed.");
      return;
    }
    if (!mounted) return; // Verificar si el widget sigue montado

    setState(() { _isSaving = true; _saveError = null; });

    final customerData = {
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(), // Incluir teléfono
    };

    final wcService = context.read<WooCommerceService>(); // Obtener servicio
    final scaffoldMessenger = ScaffoldMessenger.of(context); // Capturar ScaffoldMessenger
    final navigator = Navigator.of(context); // Capturar Navigator

    try {
      debugPrint("_saveCustomer: Calling createCustomer service...");
      // El servicio ahora devuelve Map<String, dynamic> o lanza excepción
      final newCustomer = await wcService.createCustomer(customerData);

      if (!mounted) return;

      if (newCustomer['id'] != null) { // Éxito si hay ID
        final String customerId = newCustomer['id'].toString();
        final String firstName = newCustomer['first_name'] ?? '';
        final String lastName = newCustomer['last_name'] ?? '';
        final String displayName = (firstName + ' ' + lastName).trim().isEmpty
            ? (newCustomer['email'] ?? 'Cliente $customerId')
            : (firstName + ' ' + lastName).trim();

        debugPrint("Cliente creado en WC: ID $customerId, Nombre: $displayName");

        if (_saveToDeviceContacts) {
          debugPrint("Intentando guardar contacto en dispositivo...");
          // No esperar (await) para no bloquear la UI principal por esto
          _trySaveContactToDevice(firstName, lastName, customerData['email']!, customerData['phone']!);
        }

        setState(() { _isSaving = false; });
        // Devolver los datos del cliente creado a la pantalla anterior
        navigator.pop({'id': customerId, 'name': displayName});

      } else { // No debería ocurrir si el servicio lanza excepciones correctamente
        debugPrint("_saveCustomer: createCustomer returned non-null but without ID.");
        setState(() {
          _saveError = "Respuesta inválida del servidor al crear.";
          _isSaving = false;
        });
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(_saveError!), backgroundColor: Colors.orange));
      }

    } on NetworkException catch (e) {
      debugPrint("_saveCustomer: NetworkException caught: $e");
      if (!mounted) return;
      setState(() { _saveError = "Error de red: ${e.message}"; _isSaving = false; });
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(_saveError!), backgroundColor: Colors.orange.shade800));
    } on InvalidDataException catch (e) { // Ej. email duplicado
      debugPrint("_saveCustomer: InvalidDataException caught: $e");
      if (!mounted) return;
      setState(() { _saveError = "Error en datos: ${e.message}"; _isSaving = false; });
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(_saveError!), backgroundColor: Colors.orange));
    } on ApiException catch (e) { // Otros errores API
      debugPrint("_saveCustomer: ApiException caught: $e");
      if (!mounted) return;
      setState(() { _saveError = "Error API: ${e.message}"; _isSaving = false; });
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(_saveError!), backgroundColor: Colors.red.shade700));
    } catch (e) { // Errores inesperados
      debugPrint("_saveCustomer: Unexpected error caught: $e");
      if (!mounted) return;
      setState(() { _saveError = "Error inesperado: ${e.toString()}"; _isSaving = false; });
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(_saveError!), backgroundColor: Colors.red));
    }
  }

  Future<void> _trySaveContactToDevice(String firstName, String lastName, String email, String phone) async {
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context); // Usar el contexto del widget
    try {
      final granted = await Permission.contacts.request().isGranted;
      if (!mounted) return;

      if (granted) {
        final newContact = Contact()
          ..name.first = firstName
          ..name.last = lastName;
        if (email.isNotEmpty) { newContact.emails = [Email(email)];}
        if (phone.isNotEmpty) { newContact.phones = [Phone(phone)]; }

        await FlutterContacts.insertContact(newContact);
        debugPrint("... Contacto guardado en dispositivo exitosamente.");
        if (mounted) {
          scaffoldMessenger.showSnackBar(const SnackBar(content: Text("Guardado en contactos del dispositivo."), duration: Duration(seconds: 2), backgroundColor: Colors.green,));
        }
      } else {
        debugPrint("... Permiso de escritura de contactos denegado.");
        if (mounted) {
          scaffoldMessenger.showSnackBar(const SnackBar(content: Text("No se pudo guardar en contactos (permiso denegado)."), backgroundColor: Colors.orange,));
        }
      }
    } catch(e) {
      debugPrint("... Error guardando contacto en dispositivo: $e");
      if (mounted) {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text("Error al guardar en contactos: $e"), backgroundColor: Colors.red,));
      }
    }
  }

  Future<void> _pickContact() async {
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final PermissionStatus status = await Permission.contacts.request();

    if (!mounted) return;

    if (status.isGranted) {
      try {
        // Volver a pedir permiso por si acaso (readonly)
        if (await FlutterContacts.requestPermission(readonly: true)) {
          final Contact? contact = await FlutterContacts.openExternalPick();
          if (!mounted) return;

          if (contact != null) {
            _populateFieldsFromContact(contact);
            scaffoldMessenger.showSnackBar( const SnackBar(content: Text("Datos de contacto cargados"), backgroundColor: Colors.blueGrey), );
          } else { debugPrint("Selector de contactos cancelado por usuario."); }
        } else if (mounted) {
          scaffoldMessenger.showSnackBar( const SnackBar(content: Text("Permiso de lectura de contactos denegado"), backgroundColor: Colors.orange), );
        }
      } catch (e) {
        debugPrint("Error buscando contactos: $e");
        if (mounted) { scaffoldMessenger.showSnackBar( SnackBar(content: Text("Error al acceder a contactos: $e"), backgroundColor: Colors.red), ); }
      }
    } else {
      debugPrint("Permiso de contactos denegado.");
      if (mounted) { scaffoldMessenger.showSnackBar( const SnackBar(content: Text("Permiso de contactos necesario"), backgroundColor: Colors.orange), ); }
    }
  }

  void _populateFieldsFromContact(Contact contact) {
    setState(() {
      _firstNameController.text = contact.name.first;
      _lastNameController.text = contact.name.last;
      if (_firstNameController.text.isEmpty && _lastNameController.text.isEmpty) {
        _firstNameController.text = contact.displayName;
      }
      _emailController.text = contact.emails.firstOrNull?.address ?? '';
      String phoneCleaned = contact.phones.firstOrNull?.number.replaceAll(RegExp(r'[^\d+]'), '') ?? '';
      _phoneController.text = phoneCleaned;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        title: 'Nuevo Cliente',
        showBackButton: true,
        onBackPressed: () => Navigator.maybePop(context),
        showCartButton: false,
        showSettingsButton: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.contact_phone_outlined, size: 18),
                  label: const Text('Buscar en Contactos'),
                  onPressed: _isSaving ? null : _pickContact,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                      side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10)
                  ),
                ),
              ),
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                textCapitalization: TextCapitalization.words,
                validator: (v)=>(v==null||v.trim().isEmpty)?'Nombre requerido':null,
                textInputAction: TextInputAction.next,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Apellido *'),
                textCapitalization: TextCapitalization.words,
                validator: (v)=>(v==null||v.trim().isEmpty)?'Apellido requerido':null,
                textInputAction: TextInputAction.next,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Correo Electrónico *'),
                keyboardType: TextInputType.emailAddress,
                validator: (v){
                  if(v==null||v.trim().isEmpty)return 'Correo requerido';
                  if(!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(v.trim())) {
                    return 'Formato de correo inválido';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration( labelText: 'Teléfono (Opcional)', prefixIcon: Icon(Icons.phone), ),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\+?\d*'))],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) { if (!_isSaving) _saveCustomer(); },
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text("Guardar en contactos del dispositivo"),
                value: _saveToDeviceContacts,
                onChanged: _isSaving ? null : (bool? value) { setState(() { _saveToDeviceContacts = value ?? false; }); },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(_saveError!, style: TextStyle(color: Colors.red.shade700), textAlign: TextAlign.center),
                ),
              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'GUARDANDO...' : 'GUARDAR CLIENTE'),
                onPressed: _isSaving ? null : _saveCustomer,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
