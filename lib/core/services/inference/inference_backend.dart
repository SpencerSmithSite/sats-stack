import 'dart:async';

import 'package:http/http.dart' as http;

/// A source of generated answers.
///
/// Sats Stack offers several, chosen by the user: a local or LAN Ollama server,
/// an OpenAI-compatible endpoint, the device's own built-in model, or a small
/// open model downloaded on request. They differ enough — in availability, in
/// context size, and crucially in whether anything leaves the device — that
/// those properties belong on the interface rather than being assumed.
///
/// Before this existed the app had a flat `AiProvider` enum and a facade that
/// switched on it. That worked while every provider was an HTTP endpoint with a
/// URL and a model name. The on-device backends are neither: one has no URL, no
/// model list and an availability state the OS owns, and the other has a
/// multi-gigabyte download the user has to consent to. Those do not fit an enum
/// arm.
abstract class InferenceBackend {
  /// Stable identifier, persisted in `AppSettings`.
  String get id;

  /// Name shown in the backend picker.
  String get displayName;

  /// One line describing what this backend is, for the picker.
  String get description;

  /// Whether answers are generated without anything leaving the device.
  ///
  /// Drives the privacy disclosure. Sats Stack is chosen partly for being
  /// local-first with no account and no cloud, so a backend that sends the
  /// user's financial data to a hosted service must say so plainly rather than
  /// letting a blanket "everything stays on your device" claim stand.
  bool get isPrivate;

  /// How much financial context to include in a prompt, in characters.
  ///
  /// Varies by an order of magnitude across backends: Apple's on-device model
  /// and Gemini Nano have small windows, while a hosted model has a very large
  /// one. A single fixed budget is wrong for almost all of them, and
  /// overfilling a small window degrades the answer rather than erroring — so
  /// the system prompt builder must send fewer transactions here, not truncated
  /// ones.
  int get contextBudgetChars;

  /// Whether this backend can serve a request right now — server reachable, key
  /// present, platform model supported and enabled on this hardware.
  ///
  /// Cheap enough to call on screen load; implementations should time out
  /// rather than hang.
  Future<BackendStatus> checkStatus();

  /// Stream an answer token by token. Throws [InferenceException] on failure.
  ///
  /// [messages] is the OpenAI-shaped `{'role': ..., 'content': ...}` list the
  /// chat screen already builds. Backends that take a single prompt flatten it
  /// via [flattenMessages] rather than making every caller do so.
  ///
  /// If [client] is provided it is used for the request but NOT closed — the
  /// caller owns its lifecycle. Ignored by backends that do not use HTTP.
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  });

  /// Models this backend offers, if it offers a choice. Empty for the platform
  /// backends, which ship exactly one model and do not name it.
  Future<List<String>> availableModels() async => const [];

  void dispose() {}

  /// Collapse a chat transcript into one prompt plus its system instructions.
  ///
  /// The session-based on-device APIs — Apple's `LanguageModelSession` and ML
  /// Kit's `generateContentStream` — take instructions and a single prompt, not
  /// a role-tagged list. Speaker labels are kept so a multi-turn conversation
  /// still reads as one, which matters because these models are small enough to
  /// lose the thread without them.
  static ({String? system, String prompt}) flattenMessages(
    List<Map<String, String>> messages,
  ) {
    final system = messages
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'] ?? '')
        .where((c) => c.isNotEmpty)
        .join('\n\n');

    final turns = messages.where((m) => m['role'] != 'system').toList();

    // A single user turn is by far the common case — the monthly insight, and
    // the first message of any chat. Labelling that one "User:" would be noise
    // the model might echo.
    if (turns.length == 1) {
      return (
        system: system.isEmpty ? null : system,
        prompt: turns.first['content'] ?? '',
      );
    }

    final prompt = turns
        .map((m) =>
            '${m['role'] == 'assistant' ? 'Assistant' : 'User'}: ${m['content'] ?? ''}')
        .join('\n\n');

    return (system: system.isEmpty ? null : system, prompt: prompt);
  }
}

/// Result of an availability check, carrying a reason when unavailable so the
/// UI can tell the user what to fix rather than just greying something out.
class BackendStatus {
  final bool available;
  final String? detail;

  const BackendStatus.available([this.detail]) : available = true;
  const BackendStatus.unavailable(this.detail) : available = false;
}

class InferenceException implements Exception {
  final String message;

  InferenceException(this.message);

  @override
  String toString() => message;
}

/// Fails a response body that has gone quiet.
///
/// Every backend here applied its timeout to `client.send(...)`, which
/// completes as soon as the response *headers* arrive. The body that follows
/// could then stall forever: a dropped mobile connection mid-answer left the
/// chat spinner turning with no error, and the import's cancel flag is only
/// checked when a token arrives, so that stalled too.
///
/// A gap between events is the right thing to measure rather than a total
/// budget — a long answer is not a broken one.
extension IdleTimeout<T> on Stream<T> {
  Stream<T> idleTimeout(Duration gap, String what) => timeout(
        gap,
        onTimeout: (sink) => sink.addError(
          InferenceException(
            '$what stopped responding after ${gap.inSeconds}s. '
            'Check your connection and try again.',
          ),
        ),
      );
}

/// Runs one generation at a time per platform channel.
///
/// `EventChannel.receiveBroadcastStream` installs a handler on the channel
/// name, so a second concurrent listen *replaces* the first: the earlier
/// listener then receives nothing and never completes, with no timeout to
/// rescue it. Reachable without trying — the dashboard's monthly insight
/// generating on Apple Intelligence while the user opens the AI tab and asks a
/// question — and the symptom is a spinner that never stops.
///
/// Multiplexing would need request ids on both native sides. Queueing needs
/// neither, and a queued answer is strictly better than a hung one: the second
/// request starts as soon as the first finishes.
Stream<T> serialisedOnChannel<T>(
  String channelName,
  Stream<T> Function() open,
) async* {
  final previous = _channelQueues[channelName];
  final mine = Completer<void>();
  _channelQueues[channelName] = mine;
  try {
    if (previous != null) {
      // Someone else is generating. Their failure is not ours, so ignore it.
      try {
        await previous.future;
      } catch (_) {}
    }
    yield* open();
  } finally {
    if (_channelQueues[channelName] == mine) {
      _channelQueues.remove(channelName);
    }
    if (!mine.isCompleted) mine.complete();
  }
}

final Map<String, Completer<void>> _channelQueues = {};
