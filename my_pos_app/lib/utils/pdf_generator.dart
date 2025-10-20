// lib/utils/pdf_generator.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../models/order.dart';

/// **ARCHIVO MODIFICADO**
///
/// Se han ELIMINADO las funciones relacionadas con la generación de etiquetas en PDF:
/// - `generateAndPrintLabelSheet`
/// - `printOrShareLabelPdf`
///
/// Se CONSERVAN intactas todas las funciones para generar el PDF de los pedidos,
/// ya que esta funcionalidad no debía ser alterada.
class PdfGenerator {
  // --- PROPIEDADES Y MÉTODOS PARA PEDIDOS (SIN CAMBIOS) ---
  static final currencyFormat = NumberFormat.currency(locale: 'es_CR', symbol: '₡');
  static final dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm', 'es_CR');

  // El resto de los métodos para generar PDF de pedidos no cambian
  static Future<void> printOrSharePdf(Order order, {bool share = false}) async {
    final double totalManualItemDiscounts = order.items.fold(0.0, (sum, item) => sum + (item.individualDiscount ?? 0.0));
    final double totalWcDiscounts = order.discount;
    final Map<String, dynamic> orderData = {
      'orderId': order.number ?? order.id ?? 'N/A',
      'customerName': '${order.customerName} ${order.customerId != null && order.customerId != '0' ? '(ID: ${order.customerId})' : ''}',
      'dateFormatted': dateTimeFormat.format(order.date),
      'items': order.items.map((item) => {'qty': item.quantity.toString(), 'name': item.name, 'price': currencyFormat.format(item.effectivePrice), 'subtotal': currencyFormat.format(item.effectiveSubtotal)}).toList(),
      'subtotalFormatted': currencyFormat.format(order.subtotal),
      'wcDiscountFormatted': currencyFormat.format(totalWcDiscounts),
      'manualDiscountFormatted': currencyFormat.format(totalManualItemDiscounts),
      'taxFormatted': currencyFormat.format(order.tax),
      'totalFormatted': currencyFormat.format(order.total),
      'hasWcDiscount': totalWcDiscounts > 0.01,
      'hasManualDiscount': totalManualItemDiscounts > 0.01,
    };
    final Uint8List pdfBytes = await _generateOrderPdf(orderData);
    if (share) {
      await Printing.sharePdf(bytes: pdfBytes, filename: 'pedido_${order.number ?? order.id}.pdf');
    } else {
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdfBytes, name: 'pedido_${order.number ?? order.id}.pdf');
    }
  }

  static Future<Uint8List> _generateOrderPdf(Map<String, dynamic> data) async {
    final fontData = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
    final boldFontData = await rootBundle.load("assets/fonts/Roboto-Bold.ttf");

    final pw.ThemeData theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(fontData),
      bold: pw.Font.ttf(boldFontData),
    );
    final pdf = pw.Document(theme: theme);

    final String orderId = data['orderId'] ?? 'N/A';
    final String customerName = data['customerName'] ?? 'Cliente General';
    final String dateFormatted = data['dateFormatted'] ?? '';
    final List<Map<String, String>> items = List<Map<String, String>>.from(data['items'] ?? []);
    final String subtotalFormatted = data['subtotalFormatted'] ?? '0.00';
    final String wcDiscountFormatted = data['wcDiscountFormatted'] ?? '0.00';
    final String manualDiscountFormatted = data['manualDiscountFormatted'] ?? '0.00';
    final String taxFormatted = data['taxFormatted'] ?? '0.00';
    final String totalFormatted = data['totalFormatted'] ?? '0.00';
    final bool hasWcDiscount = data['hasWcDiscount'] ?? false;
    final bool hasManualDiscount = data['hasManualDiscount'] ?? false;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(alignment: pw.Alignment.center, margin: const pw.EdgeInsets.only(bottom: 20), child: pw.Text('Resumen de Pedido', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Pedido #: $orderId', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text('Fecha: $dateFormatted')]),
            pw.SizedBox(height: 8),
            pw.Text('Cliente: $customerName'),
            pw.Divider(height: 25, thickness: 1),
            pw.Text('Detalle:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            _buildItemsTablePdf(items),
            pw.Divider(height: 25, thickness: 1),
            _buildTotalsSummaryPdf(subtotalFormatted, wcDiscountFormatted, manualDiscountFormatted, taxFormatted, totalFormatted, hasWcDiscount, hasManualDiscount),
            pw.Spacer(),
            pw.Center(child: pw.Text('--- Gracias por su compra ---', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey))),
          ]);
        },
      ),
    );
    return pdf.save();
  }

  static pw.Widget _buildItemsTablePdf(List<Map<String, String>> items) {
    final headers = ['Cant', 'Producto', 'P.Unit', 'Subtotal'];
    final data = items.map((item) => [item['qty'] ?? '?', item['name'] ?? 'N/A', item['price'] ?? '0.00', item['subtotal'] ?? '0.00']).toList();
    return pw.Table.fromTextArray( headers: headers, data: data, border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white), cellStyle: const pw.TextStyle(fontSize: 9), headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800), cellAlignment: pw.Alignment.centerLeft, cellAlignments: { 0: pw.Alignment.center, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight }, columnWidths: { 0: const pw.FixedColumnWidth(25), 1: const pw.FlexColumnWidth(3), 2: const pw.FixedColumnWidth(65), 3: const pw.FixedColumnWidth(65) } );
  }

  static pw.Widget _buildTotalsSummaryPdf(String subtotalF, String wcDiscountF, String manualDiscountF, String taxF, String totalF, bool hasWcDisc, bool hasManualDisc) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 200,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [ pw.Text('Subtotal (Base):', style: const pw.TextStyle(fontSize: 9)), pw.Text(subtotalF, style: const pw.TextStyle(fontSize: 9))])),
            if (hasWcDisc) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [ pw.Text('Dcto. Ofertas:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.green700)), pw.Text('-$wcDiscountF', style: const pw.TextStyle(fontSize: 9, color: PdfColors.green700))])),
            if (hasManualDisc) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [ pw.Text('Dcto. Manual Items:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.green700)), pw.Text('-$manualDiscountF', style: const pw.TextStyle(fontSize: 9, color: PdfColors.green700))])),
            pw.Divider(height: 5, thickness: 0.5, color: PdfColors.grey400),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [ pw.Text('IVA:', style: const pw.TextStyle(fontSize: 9)), pw.Text(taxF, style: const pw.TextStyle(fontSize: 9))])),
            pw.Divider(height: 5, thickness: 0.5, color: PdfColors.grey400),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [ pw.Text('Total:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)), pw.Text(totalF, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))])),
          ],
        ),
      ),
    );
  }
}