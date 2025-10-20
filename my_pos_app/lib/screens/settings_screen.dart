// lib/screens/settings_screen.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

import '../providers/app_state_provider.dart';
import '../providers/order_provider.dart';
import '../services/storage_service.dart';
import '../services/sync_manager.dart';
import '../locator.dart';

import '../widgets/app_header.dart';
import '../widgets/dial_floating_action_button.dart';
import '../widgets/custom_fab_location.dart';
import '../config/constants.dart';
import '../config/routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _myPosApiKeyController = TextEditingController();
  final TextEditingController _consumerKeyController = TextEditingController();
  final TextEditingController _consumerSecretController = TextEditingController();
  final TextEditingController _taxRateController = TextEditingController();

  int _currentBottomNavIndex = -1;
  bool _pageIsLoading = true;
  SharedPreferences? _prefsInstance;
  bool _isTestingConnection = false;
  String? _testConnectionError;
  bool _showAPIKeys = false;
  String _appVersion = '';
  bool _useBiometrics = false;
  bool _isFirstRun = true;
  bool _showQrScanner = false;
  bool _manualScanModeEnabled = false;
  bool _rapidScanModeEnabled = false;
  bool _searchOnlyAvailableEnabled = true;
  bool _hideSearchImagesEnabled = false;
  bool _individualDiscountsEnabled = true;
  bool _scannerVibrationEnabled = true;
  bool _scannerSoundEnabled = true;
  bool _autosyncEnabled = true;
  int _syncIntervalMinutes = 15;
  late final SyncManager _syncManager;
  final Color _inactiveTrackColor = Colors.grey.shade300;
  final Color _inactiveThumbColor = Colors.grey.shade500;

  @override
  void initState() {
    super.initState();
    _syncManager = getIt<SyncManager>();
    _initializeScreen();
    if (mounted) setState(() => _currentBottomNavIndex = -1);
  }

  Future<void> _initializeScreen() async {
    if(mounted) setState(() => _pageIsLoading = true);
    try {
      _prefsInstance = await SharedPreferences.getInstance();
      if (!mounted) return;
      await _loadSettings();
      await _loadAppVersion();
      await _loadAPICredentials();
      _isFirstRun = _prefsInstance?.getBool(firstRunPrefKey) ?? true;
    } catch(e) {
      if (mounted) context.read<AppStateProvider>().setAppError("Error cargando ajustes: ${e.toString()}", durationSeconds: 10);
    } finally {
      if (mounted) setState(() => _pageIsLoading = false);
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _myPosApiKeyController.dispose();
    _consumerKeyController.dispose();
    _consumerSecretController.dispose();
    _taxRateController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = _prefsInstance;
    if (prefs == null || !mounted) return;
    if(mounted) setState(() {
      _useBiometrics = prefs.getBool(useBiometricsPrefKey) ?? false;
      _taxRateController.text = (prefs.getString(defaultTaxRatePrefKey) ?? '13.0');
      _manualScanModeEnabled = prefs.getBool(manualScanModePrefKey) ?? false;
      _rapidScanModeEnabled = prefs.getBool(rapidScanModePrefKey) ?? false;
      _searchOnlyAvailableEnabled = prefs.getBool(searchOnlyAvailablePrefKey) ?? true;
      _hideSearchImagesEnabled = prefs.getBool(hideSearchImagePrefKey) ?? false;
      _individualDiscountsEnabled = prefs.getBool(individualDiscountsEnabledPrefKey) ?? true;
      _scannerVibrationEnabled = prefs.getBool(scannerVibrationPrefKey) ?? true;
      _scannerSoundEnabled = prefs.getBool(scannerSoundPrefKey) ?? true;
      _autosyncEnabled = prefs.getBool(autosyncPrefKey) ?? true;
      _syncIntervalMinutes = prefs.getInt(syncIntervalPrefKey) ?? 15;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final orderProvider = context.read<OrderProvider>();
        orderProvider.setTaxRate((double.tryParse(_taxRateController.text.replaceAll(',','.')) ?? 13.0) / 100.0);
      }
    });
  }

  Future<void> _loadAPICredentials() async {
    if (!mounted) return;
    final storageService = getIt<StorageService>();
    try {
      final apiUrl = await storageService.getApiUrl();
      final cKey = await storageService.getConsumerKey();
      final cSecret = await storageService.getConsumerSecret();
      final myPosKey = await storageService.getMyPosApiKey();
      if (mounted) {
        _apiUrlController.text = apiUrl ?? '';
        _consumerKeyController.text = cKey ?? '';
        _consumerSecretController.text = cSecret ?? '';
        _myPosApiKeyController.text = myPosKey ?? '';
      }
    } catch (e) {
      debugPrint("Error loading API credentials: ${e.toString()}");
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = '${p.version}+${p.buildNumber}');
    } catch (e) {
      if(mounted) setState(() => _appVersion = '?.?.?');
    }
  }

  Future<bool> _checkBiometricAvailability() async {
    try {
      final a = LocalAuthentication();
      return await a.canCheckBiometrics || await a.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  Future<void> _testConnection() async {
    if (_isTestingConnection) return;
    FocusScope.of(context).unfocus();
    if(mounted) setState(() { _isTestingConnection = true; _testConnectionError = null; });

    final appState = context.read<AppStateProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final prefs = _prefsInstance;
    final navigator = Navigator.of(context);
    final bool wasFirstRun = _isFirstRun;

    try {
      final success = await appState.configureApp(
        apiUrl: _apiUrlController.text.trim(),
        consumerKey: _consumerKeyController.text.trim(),
        consumerSecret: _consumerSecretController.text.trim(),
        myPosApiKey: _myPosApiKeyController.text.trim(),
      );

      if (!mounted) return;

      if (!success) {
        if(mounted) setState(() => _testConnectionError = appState.error ?? "Error desconocido en la configuración.");
      } else {
        if(mounted) setState(() { _testConnectionError = null; _isFirstRun = false; });
        if (prefs != null) await prefs.setBool(firstRunPrefKey, false);
        scaffoldMessenger.showSnackBar(const SnackBar(content: Text('¡Conexión exitosa!'), backgroundColor: Colors.green));
        if (wasFirstRun) {
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) Routes.replaceWith(navigator.context, Routes.scanner);
        }
      }
    } finally {
      if (mounted) setState(() => _isTestingConnection = false);
    }
  }

  Future<void> _syncOnlineData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (_syncManager.isSyncing){
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Ya hay una sincronización en curso.'), backgroundColor: Colors.blueGrey, duration: Duration(seconds: 2)));
      return;
    }
    if (!_syncManager.isSyncing && mounted) {
      _syncManager.triggerSync();
    }
  }

  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('Se eliminarán las credenciales API guardadas. ¿Estás seguro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final storage = getIt<StorageService>();
              final appState = context.read<AppStateProvider>();
              await storage.clearApiCredentials();
              await appState.loadAppConfiguration();
              if(mounted) setState((){
                _apiUrlController.clear();
                _consumerKeyController.clear();
                _consumerSecretController.clear();
                _myPosApiKeyController.clear();
                _testConnectionError=null;
                _isFirstRun = true;
              });
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange.shade800),
            child: const Text('CERRAR SESIÓN'),
          ),
        ],
      ),
    );
  }

  void _showResetConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reiniciar Aplicación'),
        content: const Text(
          '¡ADVERTENCIA! Esto eliminará TODA la configuración local: credenciales API, caché de productos, historial de pedidos local y pedidos pendientes no sincronizados. Esta acción no se puede deshacer. ¿Estás seguro?',
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final storage = getIt<StorageService>();
              final appState = context.read<AppStateProvider>();
              final orderProvider = context.read<OrderProvider>();
              final prefs = _prefsInstance;
              final scaffoldMessenger = ScaffoldMessenger.of(context);

              showDialog(context: context, barrierDismissible: false, builder: (_)=> const Center(child: CircularProgressIndicator()));

              try {
                debugPrint("Iniciando Reinicio Completo...");
                await storage.clearApiCredentials();
                await Hive.deleteFromDisk();

                if (prefs != null) {
                  await prefs.clear();
                  await prefs.setBool(firstRunPrefKey, true);
                }

                await setupLocator();
                final newStorage = getIt<StorageService>();
                await newStorage.init();

                await orderProvider.clearOrder();
                await appState.loadAppConfiguration();

                if (mounted && Navigator.of(context, rootNavigator: true).canPop()){
                  Navigator.of(context, rootNavigator: true).pop();
                }
                if(mounted) {
                  setState(() {
                    _pageIsLoading = true; _testConnectionError = null; _isFirstRun = true;
                    _apiUrlController.clear(); _consumerKeyController.clear(); _consumerSecretController.clear(); _myPosApiKeyController.clear();
                  });
                  await _initializeScreen();
                }
                scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Aplicación reiniciada.'), backgroundColor: Colors.blueGrey));

              } catch (e) {
                if (mounted && Navigator.of(context, rootNavigator: true).canPop()){ Navigator.of(context, rootNavigator: true).pop(); }
                if (mounted) {
                  scaffoldMessenger.showSnackBar( SnackBar( content: Text('Error reiniciando: ${e.toString()}'), backgroundColor: Colors.red, ), );
                  if(mounted) { setState(() { _pageIsLoading = true; }); await _initializeScreen(); }
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('SÍ, REINICIAR TODO'),
          ),
        ],
      ),
    );
  }

  void _processQrCode(String data) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    bool processed = false;
    try {
      if (data.startsWith('{') && data.endsWith('}')) {
        final credentials = Map<String, dynamic>.from(jsonDecode(data));
        if (credentials['siteUrl'] != null && credentials['apiKey'] != null) {
          if (mounted) {
            context.read<AppStateProvider>().setConnectionMode('plugin');
            setState(() {
              _apiUrlController.text = credentials['siteUrl'] ?? '';
              _myPosApiKeyController.text = credentials['apiKey'] ?? '';
              _consumerKeyController.clear();
              _consumerSecretController.clear();
            });
            processed = true;
            scaffoldMessenger.showSnackBar(const SnackBar(content: Text('¡Datos del plugin cargados!'), backgroundColor: Colors.green));
          }
        }
      }

      if (processed) {
        if(mounted) setState(() => _showQrScanner = false);
        if (_apiUrlController.text.trim().isNotEmpty) _testConnection();
      } else {
        scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Formato de QR no reconocido.'), backgroundColor: Colors.orange));
        if (mounted) setState(() => _showQrScanner = false);
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error procesando QR: ${e.toString()}'), backgroundColor: Colors.red));
      if (mounted) setState(() => _showQrScanner = false);
    }
  }

  Widget _buildInstructionStep(int step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 22, height: 22,
            decoration: BoxDecoration( color: Theme.of(context).primaryColor, shape: BoxShape.circle, ),
            child: Center( child: Text( step.toString(), style: const TextStyle( color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, ), ), ),
          ),
          const SizedBox(width: 12),
          Expanded( child: Text( text, style: const TextStyle(fontSize: 14), ), ),
        ],
      ),
    );
  }

  Widget _buildFirstRunScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text( 'Bienvenido a MY POS MOBILE BARCODE', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row( children: [ Icon(Icons.info_outline, color: Theme.of(context).primaryColor, size: 24), const SizedBox(width: 8), const Text('Configuración inicial', style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, )), ], ),
                  const SizedBox(height: 16),
                  const Text('Para conectar la aplicación con tu tienda WooCommerce:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500,)),
                  const SizedBox(height: 12),
                  _buildInstructionStep(1, 'Ve a tu panel de WordPress > POS Mobil App'),
                  _buildInstructionStep(2, 'Genera un QR de vinculación'),
                  _buildInstructionStep(3, 'Presiona "ESCANEAR QR" y apunta tu cámara al código'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () { if(mounted) setState(() { _showQrScanner = true; }); },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('ESCANEAR QR DE CONEXIÓN'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () { if(mounted) setState(() { _isFirstRun = false; }); },
                      child: const Text('O configurar manualmente'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrScanner() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode?.rawValue != null) {
              debugPrint('Barcode found! ${barcode!.rawValue}');
              _processQrCode(barcode.rawValue!);
            }
          },
          errorBuilder: (context, error, child) {
            return Center(child: Text("Error del escáner: ${error.errorDetails?.message ?? error.errorCode.name}", style: const TextStyle(color: Colors.white)));
          },
        ),
        Container( color: Colors.black.withOpacity(0.5), child: Center( child: Column( mainAxisSize: MainAxisSize.min, children: [ Container( width: MediaQuery.of(context).size.width * 0.7, height: MediaQuery.of(context).size.width * 0.5, decoration: BoxDecoration( border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(12), ), ), const SizedBox(height: 16), const Text( 'Apunta al código QR generado por el plugin', style: TextStyle( color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, ), textAlign: TextAlign.center, ), ], ), ), ),
        Positioned( top: 16, left: 16, child: ElevatedButton.icon( onPressed: () { if(mounted) setState(() { _showQrScanner = false; }); }, icon: const Icon(Icons.arrow_back), label: const Text('VOLVER'), style: ElevatedButton.styleFrom( backgroundColor: Colors.white.withOpacity(0.8), foregroundColor: Colors.black, ), ), ),
      ],
    );
  }

  Widget _buildSettingsListView(BuildContext context, SharedPreferences prefs) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final List<Widget Function(BuildContext, SyncManager)> currentSectionBuilders = [
              (ctx, sm) => _ApiConfigSection(
            apiUrlController: _apiUrlController,
            myPosApiKeyController: _myPosApiKeyController,
            consumerKeyController: _consumerKeyController,
            consumerSecretController: _consumerSecretController,
            showAPIKeys: _showAPIKeys,
            isTestingConnection: _isTestingConnection,
            testConnectionError: _testConnectionError,
            onShowKeysToggle: () { if(mounted) setState(() => _showAPIKeys = !_showAPIKeys); },
            onTestConnection: _testConnection,
            onScanQr: () { if(mounted) setState(() => _showQrScanner = true); },
          ),
        ];

        if (appState.isAppConfigured) {
          currentSectionBuilders.addAll([
                (ctx, sm) => _SyncSettingsSection(
              prefs: prefs, autosyncEnabled: _autosyncEnabled, syncIntervalMinutes: _syncIntervalMinutes,
              inactiveTrackColor: _inactiveTrackColor, inactiveThumbColor: _inactiveThumbColor,
              onAutosyncChanged: (v) async { if(mounted) setState(() => _autosyncEnabled = v); await prefs.setBool(autosyncPrefKey, v); },
              onIntervalChanged: (v) async { if (v != null) { if(mounted) setState(() => _syncIntervalMinutes = v); await prefs.setInt(syncIntervalPrefKey, v); }},
              onSyncNow: _syncOnlineData, syncManager: sm,
            ),
                (ctx, sm) => _ScannerSettingsSection(
              prefs: prefs,
              manualScanModeEnabled: _manualScanModeEnabled,
              rapidScanModeEnabled: _rapidScanModeEnabled,
              searchOnlyAvailableEnabled: _searchOnlyAvailableEnabled,
              hideSearchImagesEnabled: _hideSearchImagesEnabled,
              scannerVibrationEnabled: _scannerVibrationEnabled,
              scannerSoundEnabled: _scannerSoundEnabled,
              taxRateController: _taxRateController,
              inactiveTrackColor: _inactiveTrackColor,
              inactiveThumbColor: _inactiveThumbColor,
              onManualScanChanged: (v) async { if(mounted) setState(() => _manualScanModeEnabled = v); await prefs.setBool(manualScanModePrefKey, v); },
              onRapidScanChanged: (v) async { if(mounted) setState(() => _rapidScanModeEnabled = v); await prefs.setBool(rapidScanModePrefKey, v); },
              onSearchOnlyAvailableChanged: (v) async { if(mounted) setState(() => _searchOnlyAvailableEnabled = v); await prefs.setBool(searchOnlyAvailablePrefKey, v); },
              onHideImagesChanged: (v) async { if(mounted) setState(() => _hideSearchImagesEnabled = v); await prefs.setBool(hideSearchImagePrefKey, v); },
              onVibrationChanged: (v) async { if(mounted) setState(() => _scannerVibrationEnabled = v); await prefs.setBool(scannerVibrationPrefKey, v); },
              onSoundChanged: (v) async { if(mounted) setState(() => _scannerSoundEnabled = v); await prefs.setBool(scannerSoundPrefKey, v); },
              onTaxRateChanged: (v) async {
                final rate = double.tryParse(v.replaceAll(',','.')) ?? 0.0;
                await prefs.setString(defaultTaxRatePrefKey, rate.toStringAsFixed(1));
                if (mounted) { context.read<OrderProvider>().setTaxRate(rate / 100.0); }
              },
            ),
                (ctx, sm) => _DiscountSettingsSection(
              prefs: prefs, individualDiscountsEnabled: _individualDiscountsEnabled,
              inactiveTrackColor: _inactiveTrackColor, inactiveThumbColor: _inactiveThumbColor,
              onDiscountsChanged: (v) async { if(mounted) setState(() => _individualDiscountsEnabled = v); await prefs.setBool(individualDiscountsEnabledPrefKey, v); },
            ),
                (ctx, sm) => _SecuritySection(
              prefs: prefs, useBiometrics: _useBiometrics, checkBiometricAvailability: _checkBiometricAvailability,
              inactiveTrackColor: _inactiveTrackColor, inactiveThumbColor: _inactiveThumbColor,
              onBiometricsChanged: (v) async { if(mounted) setState(() => _useBiometrics = v); await prefs.setBool(useBiometricsPrefKey, v); },
              onPinConfigure: () { ScaffoldMessenger.of(ctx).showSnackBar( const SnackBar( content: Text('Función PIN próximamente'), ), ); },
            ),
                (ctx, sm) => _AccountSection(
              onLogout: () => _showLogoutConfirmDialog(ctx),
              onReset: () => _showResetConfirmDialog(ctx),
            ),
          ]);
        }

        final int itemCount = currentSectionBuilders.length + 1;

        return ListView.builder(
          padding: const EdgeInsets.all(16).copyWith(bottom: 80),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index < currentSectionBuilders.length) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: currentSectionBuilders[index](context, _syncManager),
              );
            } else {
              return Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Center( child: Text( 'MY POS MOBILE BARCODE v$_appVersion', style: TextStyle( color: Colors.grey.shade600, fontSize: 12, ), ), ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildBottomNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int itemIndex,
    required bool isSelected,
  }) {
    final Color color = isSelected ? Theme.of(context).primaryColor : Colors.grey.shade600;
    return Expanded(
      child: InkWell(
        onTap: () => _onBottomNavTap(itemIndex),
        borderRadius: BorderRadius.circular(4.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    if (!mounted) return;
    setState(() => _currentBottomNavIndex = index);
    if (index == 0) {
      Routes.replaceWith(context, Routes.scanner);
    } else if (index == 1) {
      Routes.replaceWith(context, Routes.order);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final bool canGoBack = Navigator.canPop(context);
    final bool actuallyShowFirstRunScreen = _isFirstRun && !appState.isAppConfigured;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppHeader(
        title: 'Configuración',
        showSearchButton: false,
        showBackButton: canGoBack && (!actuallyShowFirstRunScreen || _showQrScanner),
        showSettingsButton: false,
        showCartButton: true,
        onBackPressed: (canGoBack && (!actuallyShowFirstRunScreen || _showQrScanner))
            ? () { if (_showQrScanner) { if(mounted) setState(() => _showQrScanner = false); } else { Navigator.pop(context); } }
            : null,
      ),
      body: Stack(
        children: [
          _pageIsLoading && !actuallyShowFirstRunScreen
              ? const Center(child: CircularProgressIndicator())
              : _showQrScanner
              ? _buildQrScanner()
              : actuallyShowFirstRunScreen
              ? _buildFirstRunScreen()
              : _prefsInstance != null
              ? _buildSettingsListView(context, _prefsInstance!)
              : const Center(child: Text("Error al cargar preferencias.")),
        ],
      ),
      floatingActionButton: const DialFloatingActionButton(),
      floatingActionButtonLocation: const LoweredCenterDockedFabLocation(downwardShift: 10.0),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        clipBehavior: Clip.antiAlias,
        color: theme.bottomAppBarTheme.color ?? theme.colorScheme.surface,
        elevation: 8.0,
        child: SizedBox(
          height: kBottomNavigationBarHeight,
          child: Row(
            children: <Widget>[
              _buildBottomNavItem(context: context, icon: Icons.qr_code_scanner, label: 'CÓDIGO', itemIndex: 0, isSelected: _currentBottomNavIndex == 0),
              const Spacer(),
              _buildBottomNavItem(context: context, icon: Icons.receipt_long_outlined, label: 'PEDIDOS', itemIndex: 1, isSelected: _currentBottomNavIndex == 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiConfigSection extends StatelessWidget {
  final TextEditingController apiUrlController;
  final TextEditingController myPosApiKeyController;
  final TextEditingController consumerKeyController;
  final TextEditingController consumerSecretController;
  final bool showAPIKeys;
  final bool isTestingConnection;
  final String? testConnectionError;
  final VoidCallback onShowKeysToggle;
  final VoidCallback onTestConnection;
  final VoidCallback onScanQr;

  const _ApiConfigSection({
    Key? key,
    required this.apiUrlController,
    required this.myPosApiKeyController,
    required this.consumerKeyController,
    required this.consumerSecretController,
    required this.showAPIKeys,
    required this.isTestingConnection,
    this.testConnectionError,
    required this.onShowKeysToggle,
    required this.onTestConnection,
    required this.onScanQr,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final bool fieldsEnabled = !appState.isLoading && !isTestingConnection;
        final String? displayError = testConnectionError ?? appState.error;
        final bool usePluginMode = appState.connectionMode == 'plugin';

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.link),
                    const SizedBox(width: 8),
                    const Text('Conexión API', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (appState.isAppConfigured)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)), child: Text('Conectado', style: TextStyle(color: Colors.green.shade800, fontSize: 12, fontWeight: FontWeight.w500)))
                    else if (displayError != null && !isTestingConnection && !appState.isLoading)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)), child: Text('Error', style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.w500)))
                    else if (isTestingConnection || appState.isLoading)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)), child: Text('No Conectado', style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w500))),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text("Usar Conexión por Plugin (Recomendado)"),
                  subtitle: const Text("Búsquedas más rápidas y seguras."),
                  value: usePluginMode,
                  onChanged: fieldsEnabled ? (value) {
                    appState.setConnectionMode(value ? 'plugin' : 'woocommerce');
                  } : null,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: apiUrlController,
                  decoration: const InputDecoration(labelText: 'URL del sitio WordPress', hintText: 'https://...', helperText: 'URL completa de tu tienda'),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  enabled: fieldsEnabled,
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: SizeTransition(sizeFactor: animation, child: child));
                  },
                  child: usePluginMode ?
                  Column(
                    key: const ValueKey('plugin-fields'),
                    children: [
                      TextField(
                        controller: myPosApiKeyController,
                        decoration: InputDecoration(
                            labelText: 'Plugin API Key (Clave Maestra)',
                            helperText: 'Clave generada por el plugin para registrar el dispositivo',
                            prefixIcon: const Icon(Icons.vpn_key_outlined),
                            suffixIcon: IconButton(icon: Icon(showAPIKeys ? Icons.visibility_off : Icons.visibility), onPressed: onShowKeysToggle)
                        ),
                        obscureText: !showAPIKeys,
                        enabled: fieldsEnabled,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: fieldsEnabled ? onScanQr : null,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('ESCANEAR QR DE CONEXIÓN'),
                        ),
                      ),
                    ],
                  ) :
                  Column(
                    key: const ValueKey('wc-fields'),
                    children: [
                      TextField(controller: consumerKeyController, decoration: InputDecoration(labelText: 'Consumer Key', helperText: 'Clave API ck_...'), obscureText: !showAPIKeys, enabled: fieldsEnabled),
                      const SizedBox(height: 16),
                      TextField(controller: consumerSecretController, decoration: InputDecoration(labelText: 'Consumer Secret', helperText: 'Clave API cs_...'), obscureText: !showAPIKeys, enabled: fieldsEnabled),
                    ],
                  ),
                ),
                if (displayError != null && !isTestingConnection && !appState.isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(displayError, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: fieldsEnabled ? onTestConnection : null,
                    icon: isTestingConnection ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.wifi_tethering),
                    label: const Text('PROBAR Y GUARDAR CONEXIÓN'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SyncSettingsSection extends StatelessWidget {
  final SharedPreferences prefs;
  final bool autosyncEnabled;
  final int syncIntervalMinutes;
  final Color inactiveTrackColor;
  final Color inactiveThumbColor;
  final ValueChanged<bool> onAutosyncChanged;
  final ValueChanged<int?> onIntervalChanged;
  final VoidCallback onSyncNow;
  final SyncManager syncManager;

  const _SyncSettingsSection({
    Key? key, required this.prefs, required this.autosyncEnabled, required this.syncIntervalMinutes,
    required this.inactiveTrackColor, required this.inactiveThumbColor, required this.onAutosyncChanged,
    required this.onIntervalChanged, required this.onSyncNow, required this.syncManager,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_problem),
                const SizedBox(width: 8),
                const Text('Sincronización Offline', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (syncManager.isSyncing)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.blue))),
                        const SizedBox(width: 6),
                        Text('Enviando...', style: TextStyle(color: Colors.blue.shade800, fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )
                else if (syncManager.queueLength > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Text('${syncManager.queueLength} pendiente(s)', style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text("Envío automático de operaciones guardadas localmente cuando hay conexión.", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Envío auto. al conectar'),
              subtitle: const Text('Reintentar operaciones pendientes al detectar red'),
              value: autosyncEnabled,
              inactiveTrackColor: inactiveTrackColor,
              inactiveThumbColor: inactiveThumbColor,
              onChanged: onAutosyncChanged,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                label: Text('FORZAR SINCRONIZACIÓN (${syncManager.queueLength})'),
                onPressed: (syncManager.isSyncing || syncManager.queueLength == 0) ? null : onSyncNow,
                icon: const Icon(Icons.cloud_upload_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerSettingsSection extends StatelessWidget {
  final SharedPreferences prefs;
  final bool manualScanModeEnabled;
  final bool rapidScanModeEnabled;
  final bool searchOnlyAvailableEnabled;
  final bool hideSearchImagesEnabled;
  final bool scannerVibrationEnabled;
  final bool scannerSoundEnabled;
  final TextEditingController taxRateController;
  final Color inactiveTrackColor;
  final Color inactiveThumbColor;
  final ValueChanged<bool> onManualScanChanged;
  final ValueChanged<bool> onRapidScanChanged;
  final ValueChanged<bool> onSearchOnlyAvailableChanged;
  final ValueChanged<bool> onHideImagesChanged;
  final ValueChanged<bool> onVibrationChanged;
  final ValueChanged<bool> onSoundChanged;
  final ValueChanged<String> onTaxRateChanged;

  const _ScannerSettingsSection({
    Key? key, required this.prefs, required this.manualScanModeEnabled, required this.rapidScanModeEnabled,
    required this.searchOnlyAvailableEnabled, required this.hideSearchImagesEnabled, required this.scannerVibrationEnabled,
    required this.scannerSoundEnabled, required this.taxRateController, required this.inactiveTrackColor,
    required this.inactiveThumbColor, required this.onManualScanChanged, required this.onRapidScanChanged,
    required this.onSearchOnlyAvailableChanged, required this.onHideImagesChanged, required this.onVibrationChanged,
    required this.onSoundChanged, required this.onTaxRateChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card( elevation: 1, shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(8), ), child: Padding( padding: const EdgeInsets.all(16), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Row( children: const [ Icon(Icons.qr_code_scanner), SizedBox(width: 8), Text( 'Escáner y Búsqueda', style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, ), ), ], ), const SizedBox(height: 16),
      SwitchListTile( title: const Text('Buscar solo productos disponibles'), subtitle: const Text('Oculta de los resultados los productos sin stock.'), value: searchOnlyAvailableEnabled, inactiveTrackColor: inactiveTrackColor, inactiveThumbColor: inactiveThumbColor, onChanged: onSearchOnlyAvailableChanged, contentPadding: EdgeInsets.zero, ),
      SwitchListTile( title: const Text('Modo de Escaneo Rápido'), subtitle: const Text('Añade productos al instante sin confirmación.'), value: rapidScanModeEnabled, inactiveTrackColor: inactiveTrackColor, inactiveThumbColor: inactiveThumbColor, onChanged: onRapidScanChanged, contentPadding: EdgeInsets.zero, ),
      SwitchListTile( title: const Text('Activar cámara manualmente'), subtitle: const Text('Muestra un botón para iniciar escáner en lugar de auto-iniciar'), value: manualScanModeEnabled, inactiveTrackColor: inactiveTrackColor, inactiveThumbColor: inactiveThumbColor, onChanged: onManualScanChanged, contentPadding: EdgeInsets.zero, ),
      SwitchListTile( title: const Text('Ocultar imágenes en búsqueda'), subtitle: const Text('Acelera búsqueda no cargando imgs'), value: hideSearchImagesEnabled, inactiveTrackColor: inactiveTrackColor, inactiveThumbColor: inactiveThumbColor, onChanged: onHideImagesChanged, contentPadding: EdgeInsets.zero, ), SwitchListTile( title: const Text('Vibración al escanear'), subtitle: const Text('Vibrar al detectar'), value: scannerVibrationEnabled, inactiveTrackColor: inactiveTrackColor, inactiveThumbColor: inactiveThumbColor, onChanged: onVibrationChanged, contentPadding: EdgeInsets.zero, ), SwitchListTile( title: const Text('Sonido al escanear'), subtitle: const Text('Sonido al detectar'), value: scannerSoundEnabled, inactiveTrackColor: inactiveTrackColor, inactiveThumbColor: inactiveThumbColor, onChanged: onSoundChanged, contentPadding: EdgeInsets.zero, ), Padding( padding: const EdgeInsets.only(top: 8), child: TextField( controller: taxRateController, decoration: const InputDecoration( labelText: 'Tasa impuesto (%)', hintText: '13.0', helperText: 'IVA predeterminado para nuevos pedidos', suffixText: '%', ), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [ FilteringTextInputFormatter.allow(RegExp(r'^\d*([.,])?\d{0,2}')), ], onChanged: onTaxRateChanged, ), ), ], ), ), );
  }
}

class _DiscountSettingsSection extends StatelessWidget {
  final SharedPreferences prefs;
  final bool individualDiscountsEnabled;
  final Color inactiveTrackColor;
  final Color inactiveThumbColor;
  final ValueChanged<bool> onDiscountsChanged;

  const _DiscountSettingsSection({
    Key? key, required this.prefs, required this.individualDiscountsEnabled,
    required this.inactiveTrackColor, required this.inactiveThumbColor, required this.onDiscountsChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card( elevation: 1, shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(8), ), child: Padding( padding: const EdgeInsets.all(16), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Row( children: const [ Icon(Icons.sell_outlined), SizedBox(width: 8), Text( 'Descuentos', style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, ), ), ], ), const SizedBox(height: 8), SwitchListTile( title: const Text('Permitir descuentos por producto'), subtitle: const Text('Habilita aplicar dcto. manual en cada línea'), value: individualDiscountsEnabled, inactiveTrackColor: inactiveTrackColor, inactiveThumbColor: inactiveThumbColor, onChanged: onDiscountsChanged, contentPadding: EdgeInsets.zero, ), ], ), ), );
  }
}

class _SecuritySection extends StatelessWidget {
  final SharedPreferences prefs;
  final bool useBiometrics;
  final Future<bool> Function() checkBiometricAvailability;
  final Color inactiveTrackColor;
  final Color inactiveThumbColor;
  final ValueChanged<bool> onBiometricsChanged;
  final VoidCallback onPinConfigure;

  const _SecuritySection({
    Key? key, required this.prefs, required this.useBiometrics, required this.checkBiometricAvailability,
    required this.inactiveTrackColor, required this.inactiveThumbColor, required this.onBiometricsChanged,
    required this.onPinConfigure,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card( elevation: 1, shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(8), ), child: Padding( padding: const EdgeInsets.all(16), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Row( children: const [ Icon(Icons.security), SizedBox(width: 8), Text( 'Seguridad', style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, ), ), ], ), const SizedBox(height: 16), FutureBuilder<bool>( future: checkBiometricAvailability(), builder: (context, snapshot) { final bool isBiometricAvailable = snapshot.connectionState == ConnectionState.done && snapshot.data == true; return SwitchListTile( title: const Text('Autenticación biométrica'), subtitle: Text( snapshot.connectionState == ConnectionState.waiting ? 'Verificando...' : isBiometricAvailable ? 'Usar huella o rostro al iniciar' : 'No disponible en este dispositivo', style: TextStyle(color: isBiometricAvailable ? null : Colors.grey.shade500)), value: useBiometrics && isBiometricAvailable, inactiveTrackColor: inactiveTrackColor, inactiveThumbColor: inactiveThumbColor, onChanged: isBiometricAvailable ? onBiometricsChanged : null, contentPadding: EdgeInsets.zero, ); }, ), ListTile( title: const Text('Configurar PIN de acceso'), subtitle: const Text( 'Protege la app con PIN (próximamente)', style: TextStyle(color: Colors.grey), ), trailing: const Icon(Icons.chevron_right), contentPadding: EdgeInsets.zero, onTap: onPinConfigure, ), ], ), ), );
  }
}

class _AccountSection extends StatelessWidget {
  final VoidCallback onLogout;
  final VoidCallback onReset;

  const _AccountSection({ Key? key, required this.onLogout, required this.onReset, }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card( elevation: 1, shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(8), ), child: Padding( padding: const EdgeInsets.all(16), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Row( children: const [ Icon(Icons.account_circle), SizedBox(width: 8), Text( 'Cuenta y Datos', style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, ), ), ], ), const SizedBox(height: 16), SizedBox( width: double.infinity, child: OutlinedButton.icon( icon: const Icon(Icons.logout), label: const Text('CERRAR SESIÓN'), onPressed: onLogout, style: OutlinedButton.styleFrom( foregroundColor: Colors.orange.shade800, side: BorderSide(color: Colors.orange.shade800), ), ), ), const SizedBox(height: 12), SizedBox( width: double.infinity, child: OutlinedButton.icon( icon: const Icon(Icons.delete_forever_outlined), label: const Text('REINICIAR APLICACIÓN'), onPressed: onReset, style: OutlinedButton.styleFrom( foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)), ), ), Padding( padding: const EdgeInsets.only(top: 8.0), child: Text("Elimina credenciales y todos los datos locales.", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)), ) ], ), ), );
  }
}