// lib/providers/app_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

import '../services/sync_manager.dart';

part 'app_state.freezed.dart';

enum ConnectionStatus { online, offline }

/// ✓ FASE 2 RIVERPOD: Estado inmutable para App global state
@freezed
class AppState with _$AppState {
  const factory AppState({
    @Default('plugin') String connectionMode,
    @Default(ConnectionStatus.offline) ConnectionStatus connectionStatus,
    @Default(false) bool isAppConfigured,
    @Default(true) bool isLoading,
    @Default(false) bool isFullyInitialized,
    @Default(false) bool isApiConnected, // ✅ VERIFICACIÓN API: Estado de conexión a la API
    String? apiConnectionError, // ✅ VERIFICACIÓN API: Error de conexión si existe
    String? appError,
    String? appNotification,
    @Default(false) bool isSyncing,
    @Default(SyncTask.none) SyncTask currentSyncTask,
    String? syncError,
    String? syncProgressMessage,
  }) = _AppState;

  const AppState._();

  factory AppState.initial() => const AppState();

  bool get isOnline => connectionStatus == ConnectionStatus.online;
  bool get isOffline => connectionStatus == ConnectionStatus.offline;
  bool get hasError => appError != null || syncError != null;
  bool get hasNotification => appNotification != null || syncProgressMessage != null;

  String? get displayError => appError ?? syncError;
  String? get displayNotification => appNotification ?? syncProgressMessage;
}
