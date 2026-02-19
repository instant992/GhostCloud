// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$foxAuthHash() => r'foxauth_placeholder_hash';

/// Auth state — tracks whether the user is authenticated.
///
/// Copied from [FoxAuth].
@ProviderFor(FoxAuth)
final foxAuthProvider =
    AutoDisposeNotifierProvider<FoxAuth, FoxAuthState>.internal(
  FoxAuth.new,
  name: r'foxAuthProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$foxAuthHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$FoxAuth = AutoDisposeNotifier<FoxAuthState>;
