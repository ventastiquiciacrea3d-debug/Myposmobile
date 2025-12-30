// lib/screens/improved_scanner_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Escáner mejorado con debounce y control de diálogos
class ImprovedScannerScreen extends StatefulWidget {
  final Function(String barcode)? onBarcodeScanned;
  final Function(dynamic product)? onProductFound;
  final String title;
  final bool enableManualEntry;

  const ImprovedScannerScreen({
    super.key,
    this.onBarcodeScanned,
    this.onProductFound,
    this.title = 'Escanear Producto',
    this.enableManualEntry = true,
  });

  @override
  State<ImprovedScannerScreen> createState() => _ImprovedScannerScreenState();
}

class _ImprovedScannerScreenState extends State<ImprovedScannerScreen>
    with WidgetsBindingObserver {
  // Controllers
  late MobileScannerController _scannerController;
  final TextEditingController _manualEntryController = TextEditingController();

  // Estado del escáner
  bool _isProcessing = false;
  bool _isShowingDialog = false;
  bool _isCameraActive = true;
  String? _lastScannedCode;
  Timer? _debounceTimer;

  // Configuración de debounce (1500ms como especificado)
  static const Duration _debounceDuration = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScanner();
  }

  void _initializeScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Manejar ciclo de vida de la cámara
    switch (state) {
      case AppLifecycleState.resumed:
        if (_isCameraActive && !_isShowingDialog) {
          _scannerController.start();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _scannerController.stop();
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _scannerController.dispose();
    _manualEntryController.dispose();
    super.dispose();
  }

  /// Procesar código escaneado con debounce
  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing || _isShowingDialog) {
      debugPrint('[ImprovedScanner] ⚠️ Ignorando escaneo - ya procesando');
      return;
    }

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    // Verificar si es el mismo código recién escaneado
    if (code == _lastScannedCode) {
      debugPrint('[ImprovedScanner] ⚠️ Código duplicado ignorado: $code');
      return;
    }

    // Cancelar timer anterior si existe
    _debounceTimer?.cancel();

    // Configurar nuevo timer de debounce
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted && !_isShowingDialog) {
        _processBarcode(code);
      }
    });

    debugPrint('[ImprovedScanner] 🔵 Código detectado: $code (procesando en ${_debounceDuration.inMilliseconds}ms)');
  }

  /// Procesar código de barras
  Future<void> _processBarcode(String code) async {
    if (_isProcessing || _isShowingDialog) return;

    setState(() {
      _isProcessing = true;
      _lastScannedCode = code;
    });

    debugPrint('[ImprovedScanner] 📦 Procesando código: $code');

    try {
      // Pausar escáner mientras se procesa
      await _scannerController.stop();

      // Callback al padre
      if (widget.onBarcodeScanned != null) {
        widget.onBarcodeScanned!(code);
      }

      // Aquí iría la búsqueda del producto
      // Por ahora, simulamos con un pequeño delay
      await Future.delayed(const Duration(milliseconds: 300));

      // Mostrar resultado (esto debería venir del servicio de productos)
      if (mounted) {
        await _showProductDialog(code);
      }
    } catch (e) {
      debugPrint('[ImprovedScanner] ❌ Error procesando código: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar código: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);

        // Reanudar escáner después de un delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isCameraActive && !_isShowingDialog) {
            _scannerController.start();
          }
        });
      }
    }
  }

  /// Mostrar diálogo de producto (simulado)
  Future<void> _showProductDialog(String code) async {
    if (_isShowingDialog) return;

    setState(() => _isShowingDialog = true);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Producto Encontrado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Código: $code'),
            const SizedBox(height: 8),
            const Text('Aquí se mostraría la información del producto'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CERRAR'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Callback de producto encontrado
              if (widget.onProductFound != null) {
                widget.onProductFound!({'code': code});
              }
            },
            child: const Text('AGREGAR'),
          ),
        ],
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isShowingDialog = false;
          _lastScannedCode = null; // Permitir escanear el mismo código nuevamente
        });

        // Reanudar escáner
        if (_isCameraActive) {
          _scannerController.start();
        }
      }
    });
  }

  /// Cerrar cámara (pero no salir de la pantalla)
  void _closeCamera() {
    setState(() {
      _isCameraActive = false;
    });
    _scannerController.stop();
    debugPrint('[ImprovedScanner] 📷 Cámara cerrada');
  }

  /// Abrir cámara
  void _openCamera() {
    setState(() {
      _isCameraActive = true;
    });
    _scannerController.start();
    debugPrint('[ImprovedScanner] 📷 Cámara iniciada');
  }

  /// Entrada manual de código
  void _showManualEntryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ingresar Código Manualmente'),
        content: TextField(
          controller: _manualEntryController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Código de barras o SKU',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            Navigator.of(context).pop();
            if (value.trim().isNotEmpty) {
              _processBarcode(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = _manualEntryController.text.trim();
              Navigator.of(context).pop();
              if (code.isNotEmpty) {
                _processBarcode(code);
              }
            },
            child: const Text('BUSCAR'),
          ),
        ],
      ),
    ).whenComplete(() {
      _manualEntryController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.enableManualEntry)
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: 'Entrada Manual',
              onPressed: _showManualEntryDialog,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Vista de cámara o mensaje
          if (_isCameraActive)
            _buildCameraView()
          else
            _buildCameraClosedView(),

          // Indicador de procesamiento
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Procesando...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // Controles sobre la cámara
          if (_isCameraActive)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: _buildCameraControls(theme),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        // Escáner
        MobileScanner(
          controller: _scannerController,
          onDetect: _onBarcodeDetected,
        ),

        // Overlay con línea de escaneo
        _buildScannerOverlay(),

        // Botón cerrar cámara (siempre funcional)
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'closeCamera',
            onPressed: _isProcessing ? null : _closeCamera,
            backgroundColor: Colors.red.shade700,
            child: const Icon(Icons.close, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildScannerOverlay() {
    return CustomPaint(
      painter: _ScannerOverlayPainter(),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildCameraClosedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Cámara cerrada',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Abrir Cámara'),
            onPressed: _openCamera,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraControls(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Flash
          IconButton(
            icon: Icon(
              _scannerController.torchEnabled ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              _scannerController.toggleTorch();
              setState(() {});
            },
          ),

          // Cambiar cámara
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 28),
            onPressed: () {
              _scannerController.switchCamera();
            },
          ),
        ],
      ),
    );
  }
}

/// Painter para el overlay del escáner con línea animada
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.7,
      height: size.height * 0.4,
    );

    // Dibujar overlay oscuro
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRect(scanArea)
        ..fillType = PathFillType.evenOdd,
      paint,
    );

    // Dibujar bordes del área de escaneo
    final borderPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRect(scanArea, borderPaint);

    // Dibujar esquinas
    final cornerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;

    // Esquina superior izquierda
    canvas.drawLine(
      scanArea.topLeft,
      scanArea.topLeft.translate(cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanArea.topLeft,
      scanArea.topLeft.translate(0, cornerLength),
      cornerPaint,
    );

    // Esquina superior derecha
    canvas.drawLine(
      scanArea.topRight,
      scanArea.topRight.translate(-cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanArea.topRight,
      scanArea.topRight.translate(0, cornerLength),
      cornerPaint,
    );

    // Esquina inferior izquierda
    canvas.drawLine(
      scanArea.bottomLeft,
      scanArea.bottomLeft.translate(cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanArea.bottomLeft,
      scanArea.bottomLeft.translate(0, -cornerLength),
      cornerPaint,
    );

    // Esquina inferior derecha
    canvas.drawLine(
      scanArea.bottomRight,
      scanArea.bottomRight.translate(-cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanArea.bottomRight,
      scanArea.bottomRight.translate(0, -cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
