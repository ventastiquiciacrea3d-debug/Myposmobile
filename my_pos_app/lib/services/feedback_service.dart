// lib/services/feedback_service.dart
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// ✓ PROPUESTA 7: FeedbackService - Sistema centralizado de feedback visual
///
/// Responsabilidades:
/// 1. ✅ Mensajes de éxito/error/info/warning consistentes
/// 2. ✅ Loading overlays para operaciones largas
/// 3. ✅ Confirmaciones de acciones con animaciones
/// 4. ✅ Progress indicators configurables
/// 5. ✅ Theming consistente en toda la app
class FeedbackService {
  static final FeedbackService _instance = FeedbackService._internal();
  factory FeedbackService() => _instance;
  FeedbackService._internal();

  // Colores consistentes para feedback
  static const Color _successColor = Color(0xFF4CAF50);
  static const Color _errorColor = Color(0xFFE53935);
  static const Color _warningColor = Color(0xFFFFA726);
  static const Color _infoColor = Color(0xFF42A5F5);

  /// Mostrar mensaje de éxito
  void showSuccess(String message, {
    Toast length = Toast.LENGTH_SHORT,
    ToastGravity gravity = ToastGravity.BOTTOM,
  }) {
    Fluttertoast.showToast(
      msg: "✓ $message",
      toastLength: length,
      gravity: gravity,
      backgroundColor: _successColor,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  /// Mostrar mensaje de error
  void showError(String message, {
    Toast length = Toast.LENGTH_LONG,
    ToastGravity gravity = ToastGravity.BOTTOM,
  }) {
    Fluttertoast.showToast(
      msg: "✕ $message",
      toastLength: length,
      gravity: gravity,
      backgroundColor: _errorColor,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  /// Mostrar mensaje de advertencia
  void showWarning(String message, {
    Toast length = Toast.LENGTH_LONG,
    ToastGravity gravity = ToastGravity.BOTTOM,
  }) {
    Fluttertoast.showToast(
      msg: "⚠ $message",
      toastLength: length,
      gravity: gravity,
      backgroundColor: _warningColor,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  /// Mostrar mensaje informativo
  void showInfo(String message, {
    Toast length = Toast.LENGTH_SHORT,
    ToastGravity gravity = ToastGravity.BOTTOM,
  }) {
    Fluttertoast.showToast(
      msg: "ℹ $message",
      toastLength: length,
      gravity: gravity,
      backgroundColor: _infoColor,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  /// Mostrar SnackBar con acción opcional
  void showSnackBar(
    BuildContext context,
    String message, {
    FeedbackType type = FeedbackType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    Color backgroundColor;
    IconData icon;

    switch (type) {
      case FeedbackType.success:
        backgroundColor = _successColor;
        icon = Icons.check_circle;
        break;
      case FeedbackType.error:
        backgroundColor = _errorColor;
        icon = Icons.error;
        break;
      case FeedbackType.warning:
        backgroundColor = _warningColor;
        icon = Icons.warning;
        break;
      case FeedbackType.info:
        backgroundColor = _infoColor;
        icon = Icons.info;
        break;
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Mostrar diálogo de confirmación
  Future<bool> showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = "Confirmar",
    String cancelText = "Cancelar",
    FeedbackType type = FeedbackType.warning,
    bool isDangerous = false,
  }) async {
    Color titleColor;
    IconData icon;

    switch (type) {
      case FeedbackType.success:
        titleColor = _successColor;
        icon = Icons.check_circle_outline;
        break;
      case FeedbackType.error:
        titleColor = _errorColor;
        icon = Icons.error_outline;
        break;
      case FeedbackType.warning:
        titleColor = _warningColor;
        icon = Icons.warning_amber;
        break;
      case FeedbackType.info:
        titleColor = _infoColor;
        icon = Icons.info_outline;
        break;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            Icon(icon, color: titleColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              cancelText,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDangerous ? _errorColor : titleColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              confirmText,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Mostrar loading overlay
  void showLoadingOverlay(
    BuildContext context, {
    String message = "Cargando...",
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_infoColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
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

  /// Ocultar loading overlay
  void hideLoadingOverlay(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// Mostrar progress dialog con barra de progreso
  void showProgressDialog(
    BuildContext context, {
    required String title,
    required String message,
    required double progress,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(_infoColor),
              ),
              const SizedBox(height: 8),
              Text(
                "${(progress * 100).toStringAsFixed(0)}%",
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tipos de feedback visual
enum FeedbackType {
  success,
  error,
  warning,
  info,
}
