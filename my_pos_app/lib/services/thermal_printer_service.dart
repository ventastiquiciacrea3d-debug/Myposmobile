// lib/services/thermal_printer_service.dart
import 'dart:async';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ThermalPrinterService {
  /// Obtiene una lista de dispositivos Bluetooth ya emparejados con el teléfono.
  Future<List<BluetoothInfo>> getPairedDevices() async =>
      PrintBluetoothThermal.pairedBluetooths;

  /// Se conecta a una impresora específica a través de su dirección MAC.
  Future<bool> connect(String mac) async =>
      PrintBluetoothThermal.connect(macPrinterAddress: mac);

  /// Se desconecta de la impresora actualmente conectada.
  Future<bool> disconnect() async => PrintBluetoothThermal.disconnect;

  /// Verifica si hay una conexión activa con una impresora.
  Future<bool> get isConnected async => PrintBluetoothThermal.connectionStatus;

  /// Verifica si el adaptador Bluetooth del dispositivo está encendido.
  Future<bool> getBluetoothState() async => PrintBluetoothThermal.bluetoothEnabled;

  /// Envía una lista de bytes (comandos) a la impresora conectada.
  /// **MÉTODO CORREGIDO PARA COMPATIBILIDAD CON EL PLUGIN**
  Future<bool> printCommands(List<int> bytes) async {
    if (bytes.isEmpty) return false;
    // NO convertir a Uint8List. Se pasa la List<int> directamente.
    return await PrintBluetoothThermal.writeBytes(bytes);
  }
}