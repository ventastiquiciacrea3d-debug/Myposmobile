// lib/screens/thermal_printing_screen.dart
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_pos_mobile_barcode/config/constants.dart';
import 'package:my_pos_mobile_barcode/services/thermal_printer_service.dart';
import 'package:my_pos_mobile_barcode/widgets/tspl_label_preview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/label_print_item.dart';
import '../providers/label_notifier.dart';
import '../widgets/app_header.dart';
import '../locator.dart';
import '../utils/tspl_generator.dart';
import '../services/tspl_batch_service.dart';

/// ✓ FASE 2 RIVERPOD: Migrado a ConsumerStatefulWidget
class ThermalPrintingScreen extends ConsumerStatefulWidget {
  final List<LabelPrintItem> printQueue;
  const ThermalPrintingScreen({super.key, required this.printQueue});

  @override
  ConsumerState<ThermalPrintingScreen> createState() => _ThermalPrintingScreenState();
}

class _ThermalPrintingScreenState extends ConsumerState<ThermalPrintingScreen> {
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

  // ⚡ OPTIMIZACIÓN: Generar comandos en background
  bool _isGeneratingCommands = false;
  double _generationProgress = 0.0;
  List<String> _generatedCommands = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    // ⚡ NO bloquear initState - usar post frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateCommandsInBackground();
    });
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
    debugPrint('[ThermalPrinting] 🔐 Checking Bluetooth permissions...');

    // Verificar estado actual primero
    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;

    debugPrint('[ThermalPrinting] Current permissions - Scan: $scanStatus, Connect: $connectStatus');

    // Si ya están otorgados, no solicitar de nuevo
    if (scanStatus.isGranted && connectStatus.isGranted) {
      debugPrint('[ThermalPrinting] ✅ All Bluetooth permissions already granted');
      return true;
    }

    // Solicitar permisos
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (!mounted) return false;

    final scanGranted = statuses[Permission.bluetoothScan]!.isGranted;
    final connectGranted = statuses[Permission.bluetoothConnect]!.isGranted;

    debugPrint('[ThermalPrinting] Permissions after request - Scan: $scanGranted, Connect: $connectGranted');

    if (scanGranted && connectGranted) {
      debugPrint('[ThermalPrinting] ✅ Bluetooth permissions granted');
      return true;
    } else {
      String message = "Se requieren permisos de Bluetooth para buscar y conectar impresoras.";
      if (statuses[Permission.bluetoothScan]!.isPermanentlyDenied || statuses[Permission.bluetoothConnect]!.isPermanentlyDenied) {
        message += " Por favor, actívalos desde los ajustes de la aplicación.";
        debugPrint('[ThermalPrinting] ⚠️ Permissions permanently denied, opening settings');
        openAppSettings();
      } else {
        debugPrint('[ThermalPrinting] ⚠️ Permissions denied by user');
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

  /// ⚡ OPTIMIZADO: Usar comandos pregenerados (ya no genera durante impresión)
  Future<void> _printLabels() async {
    debugPrint('[ThermalPrinting] 🖨️ Print button pressed');
    debugPrint('[ThermalPrinting] _isPrinting: $_isPrinting');
    debugPrint('[ThermalPrinting] _connected: $_connected');
    debugPrint('[ThermalPrinting] _generatedCommands.length: ${_generatedCommands.length}');

    // Validación 1: Verificar conexión
    final isConnected = await _printerService.isConnected;
    debugPrint('[ThermalPrinting] Printer isConnected: $isConnected');

    if (!isConnected || _isPrinting) {
      debugPrint('[ThermalPrinting] ❌ Cannot print: Not connected or already printing');
      if (mounted) {
        setState(() => _connected = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impresora no conectada.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Validación 2: Verificar que los comandos estén listos
    if (_generatedCommands.isEmpty) {
      debugPrint('[ThermalPrinting] ❌ Cannot print: No commands generated yet');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esperando generación de comandos...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    debugPrint('[ThermalPrinting] ✅ All validations passed, starting print...');

    setState(() {
      _isPrinting = true;
      _printProgress = 0.0;
      _printStatusMessage = 'Enviando a impresora...';
    });

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      debugPrint('[ThermalPrinting] 🖨️ Starting print job: ${_generatedCommands.length} commands');

      // Enviar comandos en chunks para no saturar el buffer
      const chunkSize = 10; // Enviar 10 comandos a la vez
      final totalCommands = _generatedCommands.length;

      for (int i = 0; i < totalCommands; i += chunkSize) {
        if (!mounted) throw Exception("Operación cancelada.");

        final end = (i + chunkSize > totalCommands) ? totalCommands : i + chunkSize;
        final chunk = _generatedCommands.sublist(i, end).join('\n');

        if (mounted) {
          setState(() {
            _printStatusMessage = 'Enviando ${end} de $totalCommands etiquetas...';
            _printProgress = end / totalCommands;
          });
        }

        // Convertir string a bytes
        final bytes = chunk.codeUnits;

        // Enviar a impresora
        if (!await _printerService.printCommands(bytes)) {
          throw Exception("Fallo al enviar comandos a la impresora.");
        }

        // Pequeña pausa entre chunks
        if (i + chunkSize < totalCommands) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      debugPrint('[ThermalPrinting] ✅ Print job completed successfully');

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('✅ ${widget.printQueue.length} etiquetas impresas'),
          backgroundColor: Colors.green,
        ),
      );

      // Limpiar cola
      ref.read(labelProvider.notifier).clearQueue();
      navigator.pop(true);

    } catch (e) {
      debugPrint('[ThermalPrinting] ❌ Print error: $e');
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error al imprimir: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
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

  /// ⚡ OPTIMIZACIÓN: Genera todos los comandos TSPL en background
  /// Usa delays estratégicos y post frame callbacks para mantener UI responsive
  Future<void> _generateCommandsInBackground() async {
    if (widget.printQueue.isEmpty || !mounted) return;

    debugPrint('[ThermalPrinting] 🚀 Starting background command generation for ${widget.printQueue.length} items');

    // Actualizar UI inmediatamente
    if (mounted) {
      setState(() {
        _isGeneratingCommands = true;
        _generationProgress = 0.0;
      });
    }

    try {
      // Dar tiempo al UI para renderizar el estado inicial
      // ⚡ Delay mínimo de 500ms para que la barra de progreso sea visible
      await Future.delayed(Duration(milliseconds: 500));

      // Preparar datos de productos SIN bloquear UI
      final productsData = <Map<String, dynamic>>[];

      for (int i = 0; i < widget.printQueue.length; i++) {
        final item = widget.printQueue[i];

        // Actualizar progreso de carga cada 5 items
        if (mounted && i % 5 == 0 && i > 0) {
          setState(() {
            _generationProgress = (i / widget.printQueue.length) * 0.3; // 30% del progreso total
          });
          // Permitir que UI se actualice
          await Future.delayed(Duration(milliseconds: 1));
        }

        // Los datos ya están en caché (displayName, displaySku)
        productsData.add({
          'name': item.displayName,
          'sku': item.displaySku,
          'price': 0.0,
          'barcode': item.barcode,
          'quantity': item.quantity,
        });
      }

      debugPrint('[ThermalPrinting] Prepared ${productsData.length} products, generating TSPL...');

      // Actualizar estado antes de generar
      if (mounted) {
        setState(() {
          _generationProgress = 0.3;
        });
      }

      // Dar tiempo al UI para actualizar
      await Future.delayed(Duration(milliseconds: 50));

      final labelState = ref.read(labelProvider);
      final settings = {
        'width': labelState.settings.labelLayout['width'] ?? 50.0,
        'height': labelState.settings.labelLayout['height'] ?? 38.0,
        'density': _printDensity.round(),
        'speed': _printSpeed.round(),
        'showName': labelState.settings.visibleAttributes['productName'] ?? true,
        'showSku': labelState.settings.visibleAttributes['sku'] ?? true,
        'showPrice': labelState.settings.visibleAttributes['price'] ?? false,
        'showBarcode': labelState.settings.visibleAttributes['barcode'] ?? true,
      };

      // Generar comandos en background con progreso
      final commands = await TsplBatchService.generateBatchInBackground(
        productsData: productsData,
        settings: settings,
        onProgress: (current, total) {
          // Usar addPostFrameCallback para actualizar UI thread de forma segura
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  // Progreso de 30% a 100%
                  _generationProgress = 0.3 + (current / total) * 0.7;
                });
              }
            });
          }
        },
      );

      debugPrint('[ThermalPrinting] ✅ Generated ${commands.length} commands successfully');

      // Actualización final
      if (mounted) {
        setState(() {
          _generatedCommands = commands;
          _isGeneratingCommands = false;
          _generationProgress = 1.0;
        });
      }

    } catch (e) {
      debugPrint('[ThermalPrinting] ❌ Error generating commands: $e');
      if (mounted) {
        setState(() {
          _isGeneratingCommands = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error preparando etiquetas: $e'),
            backgroundColor: Colors.red,
          ),
        );
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

    // ⚡ Mostrar progreso de generación de comandos
    if (_isGeneratingCommands) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.settings, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              Text(
                'Preparando etiquetas...',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _generationProgress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                '${(_generationProgress * 100).toInt()}% - ${(_generationProgress * widget.printQueue.length).toInt()} de ${widget.printQueue.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'La pantalla permanecerá responsive...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final labelState = ref.watch(labelProvider);
    final settings = labelState.settings;

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
        _buildPrintSettingsCard(settings, labelState),
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

  Widget _buildPrintSettingsCard(LabelSettings settings, labelState) {
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
    // Deshabilitar si está generando comandos o imprimiendo
    final canPrint = _connected &&
                     !_isPrinting &&
                     !_isGeneratingCommands &&
                     _generatedCommands.isNotEmpty &&
                     widget.printQueue.isNotEmpty;

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
          : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mostrar estado de comandos
          if (_isGeneratingCommands)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Preparando comandos... ${(_generationProgress * 100).toInt()}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )
          else if (_generatedCommands.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '✅ ${_generatedCommands.length} etiquetas listas',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          ElevatedButton.icon(
            icon: const Icon(Icons.print_rounded),
            label: const Text('IMPRIMIR COLA'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              backgroundColor: canPrint ? Theme.of(context).primaryColor : Colors.grey,
              disabledBackgroundColor: Colors.grey,
            ),
            onPressed: canPrint ? _printLabels : null,
          ),
        ],
      ),
    );
  }
}