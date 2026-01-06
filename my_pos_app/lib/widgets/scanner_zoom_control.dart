// lib/widgets/scanner_zoom_control.dart
import 'package:flutter/material.dart';

/// Widget para controlar el zoom/enfoque del scanner
class ScannerZoomControl extends StatelessWidget {
  final double currentZoom;
  final bool isFixedZoomEnabled;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<bool> onFixedZoomToggled;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onResetZoom;

  const ScannerZoomControl({
    super.key,
    required this.currentZoom,
    required this.isFixedZoomEnabled,
    required this.onZoomChanged,
    required this.onFixedZoomToggled,
    this.onZoomIn,
    this.onZoomOut,
    this.onResetZoom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Título y toggle de zoom fijo
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.zoom_in, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Zoom',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              // Toggle para activar/desactivar zoom fijo
              GestureDetector(
                onTap: () => onFixedZoomToggled(!isFixedZoomEnabled),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isFixedZoomEnabled ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isFixedZoomEnabled ? 'FIJO' : 'AUTO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Slider de zoom
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botón zoom out
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                onPressed: onZoomOut,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 24,
              ),

              // Slider
              SizedBox(
                width: 150,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.2),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: currentZoom,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    onChanged: onZoomChanged,
                  ),
                ),
              ),

              // Botón zoom in
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                onPressed: onZoomIn,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 24,
              ),
            ],
          ),

          // Valor actual
          Text(
            '${(currentZoom * 100).toInt()}%',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),

          // Presets rápidos
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPresetButton('Cerca', 0.0, currentZoom, onZoomChanged),
              const SizedBox(width: 4),
              _buildPresetButton('Media', 0.3, currentZoom, onZoomChanged),
              const SizedBox(width: 4),
              _buildPresetButton('Lejos', 0.5, currentZoom, onZoomChanged),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(
    String label,
    double value,
    double currentValue,
    ValueChanged<double> onTap,
  ) {
    final isSelected = (currentValue - value).abs() < 0.05;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.white.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Widget compacto de zoom (solo botones +/-)
class ScannerZoomControlCompact extends StatelessWidget {
  final double currentZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback? onLongPressZoomIn;
  final VoidCallback? onLongPressZoomOut;

  const ScannerZoomControlCompact({
    super.key,
    required this.currentZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    this.onLongPressZoomIn,
    this.onLongPressZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botón zoom in
          GestureDetector(
            onTap: onZoomIn,
            onLongPress: onLongPressZoomIn,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
          ),

          const SizedBox(height: 8),

          // Indicador de zoom
          Container(
            width: 36,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(currentZoom * 100).toInt()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Botón zoom out
          GestureDetector(
            onTap: onZoomOut,
            onLongPress: onLongPressZoomOut,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.remove, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
