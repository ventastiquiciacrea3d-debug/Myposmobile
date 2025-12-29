// lib/widgets/quote_settings_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/quote_share_service.dart';
import '../locator.dart';

class QuoteSettingsSection extends StatefulWidget {
  final SharedPreferences prefs;
  final Color? inactiveTrackColor;
  final Color? inactiveThumbColor;

  const QuoteSettingsSection({
    super.key,
    required this.prefs,
    this.inactiveTrackColor,
    this.inactiveThumbColor,
  });

  @override
  State<QuoteSettingsSection> createState() => _QuoteSettingsSectionState();
}

class _QuoteSettingsSectionState extends State<QuoteSettingsSection> {
  bool _isExpanded = false;
  late QuoteShareService _quoteService;

  // Controllers para los campos de texto
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _businessPhoneController = TextEditingController();
  final TextEditingController _businessEmailController = TextEditingController();
  final TextEditingController _businessAddressController = TextEditingController();
  final TextEditingController _whatsappMessageController = TextEditingController();
  final TextEditingController _footerNoteController = TextEditingController();
  final TextEditingController _paymentTermsController = TextEditingController();
  final TextEditingController _validityDaysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _quoteService = getIt<QuoteShareService>();
    _loadSettings();
  }

  void _loadSettings() {
    _businessNameController.text = _quoteService.businessName;
    _businessPhoneController.text = _quoteService.businessPhone;
    _businessEmailController.text = _quoteService.businessEmail;
    _businessAddressController.text = _quoteService.businessAddress;
    _whatsappMessageController.text = _quoteService.whatsappMessage;
    _footerNoteController.text = _quoteService.footerNote;
    _paymentTermsController.text = _quoteService.paymentTerms;
    _validityDaysController.text = _quoteService.validityDays.toString();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _businessAddressController.dispose();
    _whatsappMessageController.dispose();
    _footerNoteController.dispose();
    _paymentTermsController.dispose();
    _validityDaysController.dispose();
    super.dispose();
  }

  Future<void> _saveField(Future<void> Function() saveFn) async {
    await saveFn();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guardado'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Encabezado
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.receipt_long,
                      color: theme.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configuración de Cotizaciones',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Información del negocio y preferencias',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),

          // Contenido expandible
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Información del Negocio
                  _buildSectionTitle('Información del Negocio', Icons.store),
                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _businessNameController,
                    label: 'Nombre del Negocio',
                    icon: Icons.business,
                    onSubmitted: () => _saveField(() =>
                        _quoteService.setBusinessName(_businessNameController.text)),
                  ),

                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _businessPhoneController,
                    label: 'Teléfono',
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                    onSubmitted: () => _saveField(() =>
                        _quoteService.setBusinessPhone(_businessPhoneController.text)),
                  ),

                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _businessEmailController,
                    label: 'Email',
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: () => _saveField(() =>
                        _quoteService.setBusinessEmail(_businessEmailController.text)),
                  ),

                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _businessAddressController,
                    label: 'Dirección',
                    icon: Icons.location_on,
                    maxLines: 2,
                    onSubmitted: () => _saveField(() =>
                        _quoteService.setBusinessAddress(_businessAddressController.text)),
                  ),

                  const SizedBox(height: 24),

                  // Mensajes y Textos
                  _buildSectionTitle('Mensajes Personalizados', Icons.message),
                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _whatsappMessageController,
                    label: 'Mensaje de WhatsApp',
                    icon: Icons.message,
                    maxLines: 3,
                    hintText: '¡Hola! Te envío la cotización...',
                    onSubmitted: () => _saveField(() =>
                        _quoteService.setWhatsappMessage(_whatsappMessageController.text)),
                  ),

                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _footerNoteController,
                    label: 'Nota al Pie',
                    icon: Icons.note,
                    hintText: 'Gracias por su preferencia',
                    onSubmitted: () => _saveField(() =>
                        _quoteService.setFooterNote(_footerNoteController.text)),
                  ),

                  const SizedBox(height: 24),

                  // Términos y Validez
                  _buildSectionTitle('Términos y Condiciones', Icons.gavel),
                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _paymentTermsController,
                    label: 'Términos de Pago',
                    icon: Icons.payment,
                    hintText: 'Pago contra entrega',
                    onSubmitted: () => _saveField(() =>
                        _quoteService.setPaymentTerms(_paymentTermsController.text)),
                  ),

                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _validityDaysController,
                    label: 'Validez de Cotización (días)',
                    icon: Icons.calendar_today,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: () => _saveField(() {
                      final days = int.tryParse(_validityDaysController.text) ?? 15;
                      return _quoteService.setValidityDays(days);
                    }),
                  ),

                  const SizedBox(height: 16),

                  // Botón de guardar todo
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar Todos los Cambios'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        await _saveAllSettings();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Configuración guardada exitosamente'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    required Future<void> Function() onSubmitted,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          icon: const Icon(Icons.check, color: Colors.green),
          onPressed: onSubmitted,
          tooltip: 'Guardar',
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      onSubmitted: (_) => onSubmitted(),
    );
  }

  Future<void> _saveAllSettings() async {
    await _quoteService.setBusinessName(_businessNameController.text);
    await _quoteService.setBusinessPhone(_businessPhoneController.text);
    await _quoteService.setBusinessEmail(_businessEmailController.text);
    await _quoteService.setBusinessAddress(_businessAddressController.text);
    await _quoteService.setWhatsappMessage(_whatsappMessageController.text);
    await _quoteService.setFooterNote(_footerNoteController.text);
    await _quoteService.setPaymentTerms(_paymentTermsController.text);
    final days = int.tryParse(_validityDaysController.text) ?? 15;
    await _quoteService.setValidityDays(days);
  }
}
