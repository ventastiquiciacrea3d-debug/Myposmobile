// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$orderSummaryHash() => r'5a13bba864e5af53533c039a355683ad2b93c918';

/// See also [orderSummary].
@ProviderFor(orderSummary)
final orderSummaryProvider = AutoDisposeProvider<OrderSummary>.internal(
  orderSummary,
  name: r'orderSummaryProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$orderSummaryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OrderSummaryRef = AutoDisposeProviderRef<OrderSummary>;
String _$currentOrderHash() => r'392aedf441389c5f6f8711a57dde4adb898d4866';

/// Notifier para la orden actual
///
/// Copied from [CurrentOrder].
@ProviderFor(CurrentOrder)
final currentOrderProvider =
    AutoDisposeAsyncNotifierProvider<CurrentOrder, CurrentOrderState>.internal(
  CurrentOrder.new,
  name: r'currentOrderProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$currentOrderHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrentOrder = AutoDisposeAsyncNotifier<CurrentOrderState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
