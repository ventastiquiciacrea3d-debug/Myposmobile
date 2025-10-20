// lib/utils/timer_util.dart
import 'dart:async' as async;
import 'package:flutter/foundation.dart';

/// Clase útil para manejar "debouncing", es decir,
/// ejecutar una acción solo después de que ha pasado un cierto tiempo sin
/// que se vuelva a solicitar.
class Debouncer {
  final Duration duration;
  async.Timer? _timer;

  Debouncer({this.duration = const Duration(milliseconds: 500)});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = async.Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
  }
}