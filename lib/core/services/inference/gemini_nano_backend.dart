import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'inference_backend.dart';

/// What ML Kit reported about Gemini Nano on this device.
///
/// Mirrors ML Kit's own `FeatureStatus` — UNAVAILABLE, DOWNLOADABLE,
/// DOWNLOADING, AVAILABLE — plus the two cases that sit outside it: a platform
/// with no bridge, and a bridge that answered with something unrecognised.
///
/// The distinction that matters is [downloadable] versus [unavailable]. Nano's
/// weights are not on the device by default; they are fetched through AICore on
/// first use. A user whose phone *can* run Nano but has not downloaded it is
/// one tap away, and telling them "unavailable" would be wrong.
enum GeminiNanoState {
  /// Ready to answer.
  available,

  /// Supported, but the weights are not on the device yet.
  downloadable,

  /// AICore is fetching the weights now.
  downloading,

  /// This hardware or build cannot run Nano at all.
  unavailable,

  /// Not Android, or a build without the bridge.
  unsupportedPlatform,

  /// The bridge answered with something this version does not recognise.
  unknown;

  static GeminiNanoState fromReason(String? reason) => switch (reason) {
        'available' => GeminiNanoState.available,
        'downloadable' => GeminiNanoState.downloadable,
        'downloading' => GeminiNanoState.downloading,
        'unavailable' => GeminiNanoState.unavailable,
        'unsupported_platform' => GeminiNanoState.unsupportedPlatform,
        _ => GeminiNanoState.unknown,
      };

  /// Whether to show this backend in the picker at all.
  ///
  /// Same rule as Apple's: a device that can never run Nano gets no row, while
  /// one that merely needs the download does — because that row is the only
  /// place the download can be started from.
  bool get worthOffering => switch (this) {
        GeminiNanoState.available ||
        GeminiNanoState.downloadable ||
        GeminiNanoState.downloading =>
          true,
        _ => false,
      };

  /// Whether the user has something to do here.
  bool get needsDownload =>
      this == GeminiNanoState.downloadable || this == GeminiNanoState.downloading;
}

class GeminiNanoAvailability {
  final GeminiNanoState state;
  final String detail;

  const GeminiNanoAvailability(this.state, this.detail);

  bool get isAvailable => state == GeminiNanoState.available;
}

/// Google's on-device model, through ML Kit's GenAI Prompt API.
///
/// The Android counterpart to [PlatformLlmBackend]: a model the OS owns, run by
/// AICore, with nothing leaving the device. Written for Sats Stack rather than
/// ported — Council planned this backend and never built it, so there is no
/// prior implementation to copy and the notes below are the reference.
///
/// Two things differ from Apple's, and both show up in the UI:
///
/// 1. **The weights are not there by default.** Apple Intelligence downloads
///    its model as part of the OS; Nano's arrive through AICore on request. So
///    this backend has a [download] method and a progress stream, and the
///    picker has a button Apple's row does not need.
/// 2. **Hardware support is narrow.** Nano needs a recent flagship — the Pixel
///    9/10 series, Galaxy S24+ and comparable — with AICore present and the
///    bootloader locked. Most Android devices in circulation qualify for
///    neither this nor a large downloaded model, which is why the downloadable
///    Qwen catalogue remains the floor on Android rather than a fallback.
class GeminiNanoBackend implements InferenceBackend {
  static const MethodChannel _methods =
      MethodChannel('app.satsstack/gemini_nano');
  static const EventChannel _events =
      EventChannel('app.satsstack/gemini_nano_stream');
  static const EventChannel _downloadEvents =
      EventChannel('app.satsstack/gemini_nano_download');

  static GeminiNanoAvailability? _cached;

  const GeminiNanoBackend();

  static const String backendId = 'geminiNano';

  @override
  String get id => backendId;

  static bool get bridgedHere => Platform.isAndroid;

  @override
  String get displayName => 'Gemini Nano';

  @override
  String get description =>
      'Google\'s model, built into this phone. No account, no key, and your '
      'financial data never leaves the device.';

  @override
  bool get isPrivate => true;

  /// Nano's window is small — comparable to Apple's on-device model and far
  /// under a hosted one. Same consequence: summarise harder rather than send a
  /// truncated ledger.
  @override
  int get contextBudgetChars => 4000;

  static Future<GeminiNanoAvailability> availability({
    bool refresh = false,
  }) async {
    if (!refresh && _cached != null) return _cached!;

    if (!bridgedHere) {
      return _cached = const GeminiNanoAvailability(
        GeminiNanoState.unsupportedPlatform,
        'Gemini Nano is only available on Android.',
      );
    }

    try {
      final raw =
          await _methods.invokeMapMethod<String, dynamic>('availability');
      return _cached = GeminiNanoAvailability(
        GeminiNanoState.fromReason(raw?['reason'] as String?),
        raw?['detail'] as String? ?? 'Unavailable.',
      );
    } on MissingPluginException {
      return _cached = const GeminiNanoAvailability(
        GeminiNanoState.unsupportedPlatform,
        'This build of Sats Stack has no Gemini Nano support.',
      );
    } catch (e) {
      return _cached = GeminiNanoAvailability(
        GeminiNanoState.unknown,
        'Could not ask the system about Gemini Nano: $e',
      );
    }
  }

  /// Ask AICore to fetch the weights, reporting progress 0-100.
  ///
  /// ML Kit reports bytes downloaded without a reliable total, so the native
  /// side converts to a percentage where it can and emits -1 where it cannot.
  /// The UI treats -1 as indeterminate rather than as zero progress, which is
  /// the difference between a spinner and a bar that looks stuck.
  static Stream<int> download() {
    if (!bridgedHere) {
      return Stream.error(
        InferenceException('Gemini Nano is only available on Android.'),
      );
    }
    return _downloadEvents.receiveBroadcastStream().map((e) => e as int).handleError(
      (Object error) {
        throw InferenceException(
          error is PlatformException
              ? error.message ?? 'The Gemini Nano download failed.'
              : error.toString(),
        );
      },
    );
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

    // Nano's Prompt API takes one prompt and has no separate system role, so
    // the instructions are prepended. Small models are inconsistent about
    // honouring a system turn even where one exists, and the system prompt here
    // carries the financial figures the answer has to be grounded in.
    final prompt = flat.system == null
        ? flat.prompt
        : '${flat.system}\n\n${flat.prompt}';

    return _events
        .receiveBroadcastStream({'prompt': prompt})
        .map((event) => event as String)
        .handleError((Object error) {
          throw InferenceException(
            error is PlatformException
                ? error.message ?? 'Gemini Nano failed to answer.'
                : error.toString(),
          );
        });
  }

  /// Empty on purpose: AICore serves one model and does not let the app pick.
  @override
  Future<List<String>> availableModels() async => const [];

  @override
  void dispose() {}
}
