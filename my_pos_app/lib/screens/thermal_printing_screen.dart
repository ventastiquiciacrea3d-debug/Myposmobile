// lib/screens/thermal_printing_screen.dart
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:my_pos_mobile_barcode/config/constants.dart';
import 'package:my_pos_mobile_barcode/services/thermal_printer_service.dart';
import 'package:my_pos_mobile_barcode/widgets/tspl_label_preview.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../models/label_print_item.dart';
import '../providers/label_provider.dart';
import '../widgets/app_header.dart';
import '../locator.dart';
import '../utils/tspl_generator.dart';

class ThermalPrintingScreen extends StatefulWidget {
  final List<LabelPrintItem> printQueue;
  const ThermalPrintingScreen({Key? key, required this.printQueue}) : super(key: key);

  @override
  State<ThermalPrintingScreen> createState() => _ThermalPrintingScreenState();
}

class _ThermalPrintingScreenState extends State<ThermalPrintingScreen> {
  final ThermalPrinterService _printerService = ThermalPrinterService();
  final SharedPreferences _prefs = getIt<SharedPreferences>();

  String? _selectedMacAddress;
  BluetoothInfo? _selectedDevice;
  bool _isLoading = true;
  bool _isConnecting = false;
  bool _isPrinting = false;
  bool _isRefreshingDevices = false;
  bool _connected = false;
  bool _isBluetoothEnabled = false;
  List<BluetoothInfo> _devices = [];
  String? _errorText;
  double _printDensity = 12.0;
  double _printSpeed = 4.0;

  String _printStatusMessage = '';
  double _printProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (mounted) setState(() { _isLoading = true; _errorText = null; });
    await _checkBluetoothState();
    if (_isBluetoothEnabled) {
      final permissionsGranted = await _requestPermissions();
      if (!permissionsGranted) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      await _refreshDevices();
      final alreadyConnected = await _printerService.isConnected;
      if (mounted && alreadyConnected) {
        setState(() => _connected = true);
      } else {
        final savedMac = _prefs.getString(lastConnectedPrinterPrefKey);
        if (savedMac != null && _devices.any((d) => d.macAdress == savedMac)) {
          if (mounted) {
            setState(() {
              _selectedMacAddress = savedMac;
              _selectedDevice = _devices.firstWhereOrNull((d) => d.macAdress == savedMac);
            });
            _connect();
          }
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _checkBluetoothState() async {
    final isEnabled = await _printerService.getBluetoothState();
    if (mounted) setState(() => _isBluetoothEnabled = isEnabled);
  }

  Future<void> _refreshDevices() async {
    if (!_isBluetoothEnabled || !mounted) return;
    setState(() { _isRefreshingDevices = true; _errorText = null; });
    try {
      final paired = await _printerService.getPairedDevices();
      if (mounted) setState(() => _devices = paired);
    } catch (e) {
      if (mounted) setState(() => _errorText = "Error refrescando: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isRefreshingDevices = false);
    }
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (!mounted) return false;

    if (statuses[Permission.bluetoothScan]!.isGranted && statuses[Permission.bluetoothConnect]!.isGranted) {
      return true;
    } else {
      String message = "Se requieren permisos de Bluetooth para buscar y conectar impresoras.";
      if (statuses[Permission.bluetoothScan]!.isPermanentlyDenied || statuses[Permission.bluetoothConnect]!.isPermanentlyDenied) {
        message += " Por favor, actívalos desde los ajustes de la aplicación.";
        openAppSettings();
      }
      setState(() => _errorText = message);
      return false;
    }
  }

  Future<void> _selectDevice(String? mac) async {
    if (mac == null || !mounted) return;
    if (_connected) await _disconnect();
    setState(() { _selectedMacAddress = mac; _selectedDevice = _devices.firstWhereOrNull((d) => d.macAdress == mac); });
  }

  Future<void> _connect() async {
    if (_selectedMacAddress == null || _isConnecting) return;
    setState(() => _isConnecting = true);
    if (await _printerService.isConnected) {
      await _printerService.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final success = await _printerService.connect(_selectedMacAddress!);
    if (mounted) {
      setState(() { _connected = success; _isConnecting = false; });
      if (success) {
        await _prefs.setString(lastConnectedPrinterPrefKey, _selectedMacAddress!);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conectado a ${_selectedDevice?.name}'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo conectar.'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _disconnect() async {
    await _printerService.disconnect();
    if (mounted) setState(() => _connected = false);
  }

  Future<void> _printLabels() async {
    if (!await _printerService.isConnected || _isPrinting || widget.printQueue.isEmpty) {
      if (mounted) {
        setState(() => _connected = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impresora no conectada.'), backgroundColor: Colors.orange));
      }
      return;
    }

    setState(() {
      _isPrinting = true;
      _printProgress = 0.0;
      _printStatusMessage = 'Iniciando impresión...';
    });

    final labelProvider = context.read<LabelProvider>();
    final settings = labelProvider.settings;
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    const int batchSize = 20;
    final totalItems = widget.printQueue.length;
    int itemsProcessed = 0;

    try {
      for (int i = 0; i < totalItems; i += batchSize) {
        if (!mounted) throw Exception("Operación cancelada.");

        final end = (i + batchSize > totalItems) ? totalItems : i + batchSize;
        final batchItems = widget.printQueue.sublist(i, end);

        if (mounted) {
          setState(() {
            _printStatusMessage = 'Generando lote ${i+1} - $end de $totalItems...';
          });
        }

        // Genera todos los comandos para el lote en paralelo.
        final List<List<int>> commandsList = await Future.wait(
            batchItems.map((item) => TsplGenerator.generateCommands(
              item: item,
              settings: settings,
              quantity: item.quantity,
              density: _printDensity.round(),
              speed: _printSpeed.round(),
            ))
        );

        // Concatena todos los comandos del lote en una sola lista de bytes.
        final List<int> batchCommands = commandsList.expand((list) => list).toList();

        if (!mounted) throw Exception("Operación cancelada.");

        if (mounted) {
          setState(() {
            _printStatusMessage = 'Enviando ${end} de $totalItems etiquetas...';
          });
        }

        if (!await _printerService.printCommands(batchCommands)) {
          throw Exception("Fallo al enviar lote de comandos a la impresora.");
        }

        itemsProcessed = end;
        if (mounted) {
          setState(() {
            _printProgress = itemsProcessed / totalItems;
          });
        }
        // Pequeña pausa para no saturar el buffer de la impresora.
        await Future.delayed(const Duration(milliseconds: 250));
      }

      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Impresión completada.'), backgroundColor: Colors.green));
      labelProvider.clearQueue();
      navigator.pop(true);

    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error al imprimir: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)));
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _printProgress = 0.0;
          _printStatusMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Impresión Térmica', showBackButton: true),
      body: _buildBody(),
      bottomSheet: _buildPrintButton(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (!_isBluetoothEnabled) return _buildBluetoothDisabledWarning();
    if (_errorText != null) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_errorText!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)));

    final labelProvider = context.watch<LabelProvider>();
    final settings = labelProvider.settings;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildDeviceDropdown(),
        const SizedBox(height: 20),
        _buildConnectionControls(),
        const Divider(height: 30),
        if (widget.printQueue.isNotEmpty) ...[
          const Text("Previsualización de Etiqueta", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Center(
            child: TsplLabelPreview(
              item: widget.printQueue.first,
              settings: settings,
            ),
          ),
          const Divider(height: 30),
        ],
        _buildPrintSettingsCard(settings, labelProvider),
        const Divider(height: 30),
        Text("Cola de Impresión (${widget.printQueue.length})", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (widget.printQueue.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text("La cola está vacía.")))
        else
          ...widget.printQueue.map((item) => ListTile(leading: const Icon(Icons.label_outline), title: Text(item.displayName), trailing: Text("x${item.quantity}"))),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildBluetoothDisabledWarning() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            const Text( 'Bluetooth Desactivado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center, ),
            const SizedBox(height: 12),
            Text( 'Por favor, activa el Bluetooth en los ajustes de tu dispositivo para buscar y conectar impresoras.', style: TextStyle(fontSize: 16, color: Colors.grey.shade600), textAlign: TextAlign.center, ),
            const SizedBox(height: 20),
            ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text('Volver a Comprobar'), onPressed: _loadInitialData, )
          ],
        ),
      ),
    );
  }

  Widget _buildPrintSettingsCard(LabelSettings settings, LabelProvider labelProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Ajustes de Impresión", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _buildSlider(label: "Calidad (Densidad)", value: _printDensity, min: 1, max: 15, divisions: 14, onChanged: (val) => setState(() => _printDensity = val), displayValue: _printDensity.round().toString()),
            _buildSlider(label: "Velocidad", value: _printSpeed, min: 1, max: 8, divisions: 7, onChanged: (val) => setState(() => _printSpeed = val), displayValue: _printSpeed.round().toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({required String label, required double value, required double min, required double max, required int divisions, required ValueChanged<double> onChanged, required String displayValue}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(displayValue, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
        ]),
        Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged, label: displayValue),
      ],
    );
  }

  Widget _buildDeviceDropdown() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedMacAddress,
            hint: const Text('Selecciona una impresora'),
            onChanged: (mac) => _selectDevice(mac),
            items: _devices.map((d) => DropdownMenuItem(value: d.macAdress, child: Text(d.name, overflow: TextOverflow.ellipsis))).toList(),
            decoration: const InputDecoration(labelText: 'Impresoras Emparejadas', border: OutlineInputBorder()),
            isExpanded: true,
          ),
        ),
        _isRefreshingDevices
            ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)))
            : IconButton(icon: const Icon(Icons.refresh), onPressed: _isLoading ? null : _refreshDevices, tooltip: 'Refrescar Lista'),
      ],
    );
  }

  Widget _buildConnectionControls() {
    String statusText;
    Color statusColor;
    if (_isConnecting) {
      statusText = 'Conectando...';
      statusColor = Colors.orange;
    } else if (_connected) {
      statusText = 'Conectado a ${_selectedDevice?.name ?? 'dispositivo'}';
      statusColor = Colors.green;
    } else {
      statusText = 'Desconectado';
      statusColor = Colors.red;
    }
    return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Row(children: [Icon(Icons.circle, color: statusColor, size: 16), const SizedBox(width: 8), Expanded(child: Text(statusText, overflow: TextOverflow.ellipsis))])),
      _connected ? ElevatedButton(onPressed: _disconnect, child: const Text('Desconectar')) : ElevatedButton(onPressed: (_selectedMacAddress != null && !_isConnecting) ? _connect : null, child: const Text('Conectar')),
    ])));
  }

  Widget _buildPrintButton() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2))]),
      child: _isPrinting
          ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_printStatusMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _printProgress,
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
        ],
      )
          : ElevatedButton.icon(
        icon: const Icon(Icons.print_rounded),
        label: const Text('IMPRIMIR COLA'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          backgroundColor: _connected ? Theme.of(context).primaryColor : Colors.grey,
          disabledBackgroundColor: Colors.grey,
        ),
        onPressed: _connected && !_isPrinting && widget.printQueue.isNotEmpty ? _printLabels : null,
      ),
    );
  }
}