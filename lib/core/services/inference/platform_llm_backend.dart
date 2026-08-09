import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'inference_backend.dart';

/// Why the platform's own model cannot be used, when it cannot.
///
/// Kept as a type rather than a string because the unavailable cases need
/// different treatment in the UI: some are fixable by the user and one is not,
/// and only [notEligible] should stop the option being offered at all.
enum PlatformLlmState {
  /// Ready to answer.
  available,

  /// The OS is too old for the framework to exist.
  osTooOld,

  /// The framework exists but this hardware cannot run the model.
  notEligible,

  /// Supported, but the user has not switched Apple Intelligence on.
  notEnabled,

  /// Supported and enabled; the model is still downloading.
  modelNotReady,

  /// No bridge on this platform — Android, Windows, Linux, or a build without it.
  unsupportedPlatform,

  /// The bridge answered with something this version does not recognise.
  unknown;

  static PlatformLlmState fromReason(String? reason, bool supported) {
    switch (reason) {
      case 'available':
        return PlatformLlmState.available;
      case 'device_not_eligible':
        return PlatformLlmState.notEligible;
      case 'not_enabled':
        return PlatformLlmState.notEnabled;
      case 'model_not_ready':
        return PlatformLlmState.modelNotReady;
      case 'os_too_old':
        return PlatformLlmState.osTooOld;
      default:
        return supported
            ? PlatformLlmState.unknown
            : PlatformLlmState.unsupportedPlatform;
    }
  }

  /// Whether to show this backend in the picker at all.
  ///
  /// Someone whose Mac simply cannot run Apple Intelligence is not helped by a
  /// permanently greyed-out row; someone who has merely left it switched off
  /// is, because the row tells them where the switch is.
  bool get worthOffering => switch (this) {
        PlatformLlmState.available ||
        PlatformLlmState.notEnabled ||
        PlatformLlmState.modelNotReady =>
          true,
        _ => false,
      };
}

/// A snapshot of what the platform reported.
class PlatformLlmAvailability {
  final PlatformLlmState state;
  final String detail;

  const PlatformLlmAvailability(this.state, this.detail);

  bool get isAvailable => state == PlatformLlmState.available;
}

/// Apple's on-device language model, through the Foundation Models framework.
///
/// A model already on the device, with no key, no download and no network. That
/// makes it the only generating backend that keeps the app's privacy claim
/// intact without the user having to run a server — which matters more here
/// than in most apps, because the context being sent is the user's complete
/// financial history.
///
/// Availability is asked of the platform, never inferred from a version number.
/// Apple Intelligence needs an iPhone 15 Pro or newer, so an iOS 26 device can
/// qualify while a newer OS on older silicon cannot; and only the platform can
/// distinguish hardware that will never support it from a switch the user has
/// not turned on.
class PlatformLlmBackend implements InferenceBackend {
  static const MethodChannel _methods =
      MethodChannel('app.satsstack/platform_llm');
  static const EventChannel _events =
      EventChannel('app.satsstack/platform_llm_stream');

  /// Cached because the picker, the chat screen and the status line all ask on
  /// the same frame, and the platform call is not free.
  static PlatformLlmAvailability? _cached;

  const PlatformLlmBackend();

  static const String backendId = 'appleIntelligence';

  @override
  String get id => backendId;

  /// Whether this platform has a bridge to Apple's model at all.
  ///
  /// iOS and macOS both: the framework is on each, and the same Swift file
  /// serves both runners. Gating on `isIOS` alone is the mistake that makes a
  /// Mac with Apple Intelligence silently report "no built-in model".
  static bool get bridgedHere => Platform.isIOS || Platform.isMacOS;

  @override
  String get displayName => 'Apple Intelligence';

  @override
  String get description =>
      'The model already on this device. No account, no key, no download, and '
      'your financial data never leaves it.';

  @override
  bool get isPrivate => true;

  /// Deliberately small. Apple's on-device model has a context window of a few
  /// thousand tokens, an order of magnitude under a hosted model, and
  /// overfilling it degrades the answer rather than erroring — so the system
  /// prompt must summarise further here rather than sending a truncated ledger.
  @override
  int get contextBudgetChars => 4000;

  /// Ask the platform. [refresh] skips the cache, for someone who has just gone
  /// to Settings to switch Apple Intelligence on and come back.
  static Future<PlatformLlmAvailability> availability({
    bool refresh = false,
  }) async {
    if (!refresh && _cached != null) return _cached!;

    if (!bridgedHere) {
      return _cached = const PlatformLlmAvailability(
        PlatformLlmState.unsupportedPlatform,
        'This platform has no Apple Intelligence model to use.',
      );
    }

    try {
      final raw =
          await _methods.invokeMapMethod<String, dynamic>('availability');
      final supported = raw?['supported'] as bool? ?? false;
      final state =
          PlatformLlmState.fromReason(raw?['reason'] as String?, supported);
      return _cached = PlatformLlmAvailability(
        state,
        raw?['detail'] as String? ?? 'Unavailable.',
      );
    } on MissingPluginException {
      // Running against a build without the bridge compiled in. Not an error
      // worth surfacing as a failure — the option simply is not there.
      return _cached = const PlatformLlmAvailability(
        PlatformLlmState.unsupportedPlatform,
        'This build of Sats Stack has no Apple Intelligence support.',
      );
    } catch (e) {
      return _cached = PlatformLlmAvailability(
        PlatformLlmState.unknown,
        'Could not ask the system about its model: $e',
      );
    }
  }

  @override
  Future<BackendStatus> checkStatus() async {
    final report = await availability(refresh: true);
    return report.isAvailable
        ? BackendStatus.available(report.detail)
        : BackendStatus.unavailable(report.detail);
  }

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) {
    final flat = InferenceBackend.flattenMessages(messages);
    return _events
        .receiveBroadcastStream({
          'prompt': flat.prompt,
          'system': flat.system,
        })
        .map((event) => event as String)
        .handleError((Object error) {
          throw InferenceException(
            error is PlatformException
                ? error.message ?? 'Apple Intelligence failed to answer.'
                : error.toString(),
          );
        });
  }

  /// Empty on purpose: Apple ships exactly one model and does not name it.
  /// There is nothing for a model picker to offer.
  @override
  Future<List<String>> availableModels() async => const [];

  @override
  void dispose() {}
}
