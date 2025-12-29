// lib/services/quote_share_service.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modelo de item de cotización
class QuoteItem {
  final String name;
  final int quantity;
  final double price;
  final String sku;

  QuoteItem({
    required this.name,
    required this.quantity,
    required this.price,
    this.sku = '',
  });

  double get total => quantity * price;
}

/// Servicio para compartir cotizaciones en PDF y texto
class QuoteShareService {
  static const String _prefixKey = 'quote_';

  // Keys para SharedPreferences
  static const String _businessNameKey = '${_prefixKey}business_name';
  static const String _businessPhoneKey = '${_prefixKey}business_phone';
  static const String _businessEmailKey = '${_prefixKey}business_email';
  static const String _businessAddressKey = '${_prefixKey}business_address';
  static const String _whatsappMessageKey = '${_prefixKey}whatsapp_message';
  static const String _footerNoteKey = '${_prefixKey}footer_note';
  static const String _paymentTermsKey = '${_prefixKey}payment_terms';
  static const String _validityDaysKey = '${_prefixKey}validity_days';

  SharedPreferences? _prefs;

  // Formatters
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'es_CR',
    symbol: '₡',
    decimalDigits: 2,
  );

  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'es');

  /// Inicializar el servicio
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Getters para configuración
  String get businessName => _prefs?.getString(_businessNameKey) ?? 'Mi Negocio';
  String get businessPhone => _prefs?.getString(_businessPhoneKey) ?? '';
  String get businessEmail => _prefs?.getString(_businessEmailKey) ?? '';
  String get businessAddress => _prefs?.getString(_businessAddressKey) ?? '';
  String get whatsappMessage => _prefs?.getString(_whatsappMessageKey) ??
      '¡Hola! Te envío la cotización solicitada. Cualquier duda quedo atento.';
  String get footerNote => _prefs?.getString(_footerNoteKey) ??
      'Gracias por su preferencia';
  String get paymentTerms => _prefs?.getString(_paymentTermsKey) ??
      'Pago contra entrega';
  int get validityDays => _prefs?.getInt(_validityDaysKey) ?? 15;

  // Setters para configuración
  Future<void> setBusinessName(String value) async =>
      await _prefs?.setString(_businessNameKey, value);
  Future<void> setBusinessPhone(String value) async =>
      await _prefs?.setString(_businessPhoneKey, value);
  Future<void> setBusinessEmail(String value) async =>
      await _prefs?.setString(_businessEmailKey, value);
  Future<void> setBusinessAddress(String value) async =>
      await _prefs?.setString(_businessAddressKey, value);
  Future<void> setWhatsappMessage(String value) async =>
      await _prefs?.setString(_whatsappMessageKey, value);
  Future<void> setFooterNote(String value) async =>
      await _prefs?.setString(_footerNoteKey, value);
  Future<void> setPaymentTerms(String value) async =>
      await _prefs?.setString(_paymentTermsKey, value);
  Future<void> setValidityDays(int value) async =>
      await _prefs?.setInt(_validityDaysKey, value);

  /// Generar PDF de cotización
  Future<File> generatePdf({
    required List<QuoteItem> items,
    required double subtotal,
    required double taxAmount,
    required double total,
    String quoteNumber = '',
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? notes,
  }) async {
    final pdf = pw.Document();

    // Generar número de cotización si no se proporciona
    if (quoteNumber.isEmpty) {
      final now = DateTime.now();
      quoteNumber = 'COT-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour}${now.minute}${now.second}';
    }

    final now = DateTime.now();
    final validUntil = now.add(Duration(days: validityDays));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Encabezado
          _buildPdfHeader(quoteNumber, now),
          pw.SizedBox(height: 20),

          // Información del cliente
          if (customerName != null || customerPhone != null || customerEmail != null)
            _buildCustomerInfo(customerName, customerPhone, customerEmail),

          pw.SizedBox(height: 20),

          // Tabla de productos
          _buildProductsTable(items),

          pw.SizedBox(height: 20),

          // Totales
          _buildTotalsSection(subtotal, taxAmount, total),

          pw.SizedBox(height: 20),

          // Notas adicionales
          if (notes != null && notes.isNotEmpty)
            _buildNotesSection(notes),

          pw.SizedBox(height: 10),

          // Términos y condiciones
          _buildTermsSection(validUntil),

          pw.Spacer(),

          // Pie de página
          _buildFooter(),
        ],
      ),
    );

    // Guardar PDF
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/cotizacion_$quoteNumber.pdf');
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  /// Generar texto plano de cotización (para WhatsApp/SMS)
  String generateTextQuote({
    required List<QuoteItem> items,
    required double subtotal,
    required double taxAmount,
    required double total,
    String quoteNumber = '',
    String? customerName,
    String? notes,
  }) {
    final now = DateTime.now();
    final validUntil = now.add(Duration(days: validityDays));

    if (quoteNumber.isEmpty) {
      quoteNumber = 'COT-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour}${now.minute}${now.second}';
    }

    final buffer = StringBuffer();

    // Encabezado
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📋 *COTIZACIÓN*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln();
    buffer.writeln('🏢 *$businessName*');
    if (businessPhone.isNotEmpty) buffer.writeln('📞 $businessPhone');
    if (businessEmail.isNotEmpty) buffer.writeln('📧 $businessEmail');
    if (businessAddress.isNotEmpty) buffer.writeln('📍 $businessAddress');
    buffer.writeln();
    buffer.writeln('*Cotización:* $quoteNumber');
    buffer.writeln('*Fecha:* ${_dateFormat.format(now)}');
    buffer.writeln('*Válida hasta:* ${_dateFormat.format(validUntil)}');

    if (customerName != null && customerName.isNotEmpty) {
      buffer.writeln('*Cliente:* $customerName');
    }

    buffer.writeln();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📦 *PRODUCTOS*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln();

    // Items
    for (var item in items) {
      buffer.writeln('*${item.name}*');
      if (item.sku.isNotEmpty) {
        buffer.writeln('  SKU: ${item.sku}');
      }
      buffer.writeln('  Cantidad: ${item.quantity}');
      buffer.writeln('  Precio: ${_currencyFormat.format(item.price)}');
      buffer.writeln('  Subtotal: ${_currencyFormat.format(item.total)}');
      buffer.writeln();
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('💰 *TOTALES*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln();
    buffer.writeln('Subtotal: ${_currencyFormat.format(subtotal)}');
    buffer.writeln('IVA (13%): ${_currencyFormat.format(taxAmount)}');
    buffer.writeln('*TOTAL: ${_currencyFormat.format(total)}*');
    buffer.writeln();

    if (notes != null && notes.isNotEmpty) {
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('📝 *NOTAS*');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln(notes);
      buffer.writeln();
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('*Términos de pago:* $paymentTerms');
    buffer.writeln();
    buffer.writeln(footerNote);
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

    return buffer.toString();
  }

  /// Compartir cotización por WhatsApp
  Future<void> shareViaWhatsApp({
    required List<QuoteItem> items,
    required double subtotal,
    required double taxAmount,
    required double total,
    String quoteNumber = '',
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? notes,
    String? phoneNumber,
  }) async {
    // Generar PDF
    final pdfFile = await generatePdf(
      items: items,
      subtotal: subtotal,
      taxAmount: taxAmount,
      total: total,
      quoteNumber: quoteNumber,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      notes: notes,
    );

    // Mensaje personalizado
    final message = whatsappMessage;

    // Compartir
    await Share.shareXFiles(
      [XFile(pdfFile.path)],
      text: message,
      subject: 'Cotización $quoteNumber',
    );
  }

  /// Compartir cotización por Email
  Future<void> shareViaEmail({
    required List<QuoteItem> items,
    required double subtotal,
    required double taxAmount,
    required double total,
    String quoteNumber = '',
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? notes,
  }) async {
    // Generar PDF
    final pdfFile = await generatePdf(
      items: items,
      subtotal: subtotal,
      taxAmount: taxAmount,
      total: total,
      quoteNumber: quoteNumber,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      notes: notes,
    );

    // Generar cuerpo del email
    final emailBody = '''
Estimado/a ${customerName ?? 'Cliente'},

Adjunto encontrará la cotización solicitada.

$whatsappMessage

Atentamente,
$businessName
${businessPhone.isNotEmpty ? 'Tel: $businessPhone' : ''}
${businessEmail.isNotEmpty ? 'Email: $businessEmail' : ''}
    ''';

    // Compartir
    await Share.shareXFiles(
      [XFile(pdfFile.path)],
      text: emailBody,
      subject: 'Cotización $quoteNumber - $businessName',
    );
  }

  /// Compartir solo texto (sin PDF)
  Future<void> shareTextOnly({
    required List<QuoteItem> items,
    required double subtotal,
    required double taxAmount,
    required double total,
    String quoteNumber = '',
    String? customerName,
    String? notes,
  }) async {
    final text = generateTextQuote(
      items: items,
      subtotal: subtotal,
      taxAmount: taxAmount,
      total: total,
      quoteNumber: quoteNumber,
      customerName: customerName,
      notes: notes,
    );

    await Share.share(text, subject: 'Cotización $quoteNumber');
  }

  /// Compartir con selector del sistema
  Future<void> shareGeneric({
    required List<QuoteItem> items,
    required double subtotal,
    required double taxAmount,
    required double total,
    String quoteNumber = '',
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? notes,
  }) async {
    // Generar PDF
    final pdfFile = await generatePdf(
      items: items,
      subtotal: subtotal,
      taxAmount: taxAmount,
      total: total,
      quoteNumber: quoteNumber,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      notes: notes,
    );

    // Compartir
    await Share.shareXFiles(
      [XFile(pdfFile.path)],
      text: 'Cotización $quoteNumber',
      subject: 'Cotización $quoteNumber - $businessName',
    );
  }

  // Métodos auxiliares para construir el PDF

  pw.Widget _buildPdfHeader(String quoteNumber, DateTime date) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue800,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                businessName,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              if (businessPhone.isNotEmpty)
                pw.Text(
                  businessPhone,
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
                ),
              if (businessEmail.isNotEmpty)
                pw.Text(
                  businessEmail,
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
                ),
              if (businessAddress.isNotEmpty)
                pw.Text(
                  businessAddress,
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
                ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'COTIZACIÓN',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                quoteNumber,
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.white),
              ),
              pw.Text(
                _dateFormat.format(date),
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildCustomerInfo(String? name, String? phone, String? email) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CLIENTE',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          if (name != null) pw.Text(name, style: const pw.TextStyle(fontSize: 11)),
          if (phone != null) pw.Text('Tel: $phone', style: const pw.TextStyle(fontSize: 10)),
          if (email != null) pw.Text('Email: $email', style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  pw.Widget _buildProductsTable(List<QuoteItem> items) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Encabezado
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            _buildTableCell('PRODUCTO', isHeader: true),
            _buildTableCell('SKU', isHeader: true),
            _buildTableCell('CANT.', isHeader: true, alignment: pw.Alignment.center),
            _buildTableCell('PRECIO', isHeader: true, alignment: pw.Alignment.centerRight),
            _buildTableCell('TOTAL', isHeader: true, alignment: pw.Alignment.centerRight),
          ],
        ),
        // Items
        ...items.map((item) => pw.TableRow(
          children: [
            _buildTableCell(item.name),
            _buildTableCell(item.sku),
            _buildTableCell(item.quantity.toString(), alignment: pw.Alignment.center),
            _buildTableCell(_currencyFormat.format(item.price), alignment: pw.Alignment.centerRight),
            _buildTableCell(_currencyFormat.format(item.total), alignment: pw.Alignment.centerRight),
          ],
        )),
      ],
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    pw.Alignment alignment = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      alignment: alignment,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _buildTotalsSection(double subtotal, double taxAmount, double total) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 250,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            children: [
              _buildTotalRow('Subtotal:', _currencyFormat.format(subtotal)),
              pw.SizedBox(height: 4),
              _buildTotalRow('IVA (13%):', _currencyFormat.format(taxAmount)),
              pw.Divider(color: PdfColors.grey400),
              _buildTotalRow(
                'TOTAL:',
                _currencyFormat.format(total),
                isBold: true,
                fontSize: 14,
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildTotalRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 11,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildNotesSection(String notes) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'NOTAS',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(notes, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _buildTermsSection(DateTime validUntil) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'TÉRMINOS Y CONDICIONES',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Términos de pago: $paymentTerms',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            'Validez de la cotización: hasta ${_dateFormat.format(validUntil)}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Center(
        child: pw.Text(
          footerNote,
          style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
        ),
      ),
    );
  }
}
