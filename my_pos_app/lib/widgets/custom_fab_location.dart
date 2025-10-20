// lib/widgets/custom_fab_location.dart
import 'package:flutter/material.dart';

class LoweredCenterDockedFabLocation extends FloatingActionButtonLocation {
  const LoweredCenterDockedFabLocation({
    this.downwardShift = 10.0, // Cuánto bajar el FAB. Ajusta este valor.
    this.notchMargin = 8.0,    // Margen estándar de la muesca, generalmente no necesita cambio aquí.
  });

  final double downwardShift;
  final double notchMargin;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    // Usamos la lógica de centerDocked como base.
    final Offset standardCenterDockedOffset = FloatingActionButtonLocation.centerDocked.getOffset(scaffoldGeometry);

    // Aplicamos el desplazamiento adicional hacia abajo.
    // Sumar a 'dy' mueve el widget hacia abajo en la pantalla.
    return Offset(standardCenterDockedOffset.dx, standardCenterDockedOffset.dy + downwardShift);
  }

  @override
  String toString() => 'FloatingActionButtonLocation.loweredCenterDocked';
}