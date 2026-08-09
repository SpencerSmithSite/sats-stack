import 'dart:async';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;

import '../device_memory.dart';
import '../device_storage.dart';
import 'inference_backend.dart';

/// A small open-weights model the user downloads once and then runs locally.
///
/// This is the floor for every device the platform models do not reach: most
/// Android phones, iPhones before the 15 Pro, Intel Macs, and Windows and Linux
/// desktops. It is not as good as Ollama on real hardware or a hosted model
/// behind an API key, and the picker says so rather than letting the user
/// discover it — but it is generation with no account, no key and nothing
/// leaving the device, which is otherwise unavailable to them.
///
/// Runs through `flutter_gemma`, chosen on maintenance rather than features:
/// the alternatives in this space (`fllama`, `llama_cpp_dart`, `cactus`) have
/// all gone many months between releases, and an unmaintained dependency in the
/// generation path is a liability.
class LocalModelBackend implements InferenceBackend {
  const LocalModelBackend({required this.choice});

  final LocalModelChoice choice;

  static const String backendId = 'localModel';

  @override
  String get id => backendId;

  @override
  String get displayName => 'Downloaded model';

  @override
  String get description =>
      'A small open model kept on this device. One download, then it works '
      'offline with no account and no key.';

  @override
  bool get isPrivate => true;

  /// Tied to the model actually chosen rather than fixed: a 4B model on a
  /// desktop can be given far more of the ledger than a 0.6B one on a phone,
  /// and overfilling a small window degrades the answer instead of failing.
  @override
  int get contextBudgetChars => choice.contextBudgetChars;

  @override
  Future<BackendStatus> checkStatus() async {
    if (!LocalModelChoice.runsHere) {
      return const BackendStatus.unavailable(
        'A downloaded model cannot run on this platform. Ollama or a hosted '
        'model will work here.',
      );
    }
    if (!await choice.isInstalled()) {
      return BackendStatus.unavailable(
        '${choice.name} is not downloaded yet. It is a '
        '${choice.approximateSize} one-time download.',
      );
    }
    return BackendStatus.available('${choice.name}, running on this device.');
  }

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    final model = await _LocalModelRuntime.instance.model(choice);
    final session = await model.openSession();
    try {
      // The system prompt is prepended rather than sent separately: these
      // models are small and inconsistent about honouring a separate system
      // role, and the system prompt is what carries the user's actual figures.
      final flat = InferenceBackend.flattenMessages(messages);
      final text = flat.system == null
          ? flat.prompt
          : '${flat.system}\n\n${flat.prompt}';
      await session.addQueryChunk(Message.text(text: text, isUser: true));
      yield* session.getResponseAsync();
    } catch (e) {
      throw InferenceException('The downloaded model failed to answer: $e');
    } finally {
      await session.close();
    }
  }

  @override
  Future<List<String>> availableModels() async =>
      LocalModelChoice.all.map((m) => m.name).toList();

  @override
  void dispose() {}
}

/// Loads the model once and keeps it.
///
/// Loading is expensive and the weights are large; doing it per question would
/// pay that cost on every message and risk two copies resident at once.
class _LocalModelRuntime {
  static final _LocalModelRuntime instance = _LocalModelRuntime._();
  _LocalModelRuntime._();

  InferenceModel? _model;
  String? _loadedId;

  Future<InferenceModel> model(LocalModelChoice choice) async {
    if (_model != null && _loadedId == choice.id) return _model!;
    await _model?.close();
    _model = await FlutterGemmaPlugin.instance.createModel(
      modelType: choice.modelType,
      fileType: choice.fileType,
      maxTokens: choice.maxTokens,
      // Capped because a second KV cache beside a multi-gigabyte model is how a
      // phone runs out of memory mid-answer.
      maxConcurrentSessions: 1,
    );
    _loadedId = choice.id;
    return _model!;
  }

  Future<void> unload() async {
    await _model?.close();
    _model = null;
    _loadedId = null;
  }
}

/// How a model is being offered on this particular device.
///
/// A label about *fit*, not about the model: the same weights are the "large"
/// option on a mid-range phone and the "small" one on a workstation, which is
/// the whole point of choosing per device.
enum LocalModelTier {
  /// Faster and lighter, at the cost of answer quality.
  small,

  /// The sensible default here.
  recommended,

  /// The best answers this device can produce, and the slowest.
  large;

  String get label => switch (this) {
        LocalModelTier.small => 'Smaller and faster',
        LocalModelTier.recommended => 'Recommended',
        LocalModelTier.large => 'Best answers',
      };

  /// Why someone might pick this one. Phrased as the trade being made, since
  /// every one of these is a trade rather than a ranking.
  String get rationale => switch (this) {
        LocalModelTier.small =>
          'Quickest to download and to answer. Best for straightforward '
              'questions about your spending.',
        LocalModelTier.recommended =>
          'The best balance for this device — capable enough to reason about '
              'your figures, quick enough to stay usable.',
        LocalModelTier.large =>
          'The most capable model this device can hold. Noticeably slower to '
              'answer, and a much larger download.',
      };
}

/// One downloadable model, with the numbers needed to decide whether to offer
/// it on a given device.
///
/// Sized in RAM rather than disk, because RAM is the binding constraint: the
/// model has to fit beside the app, Flutter, and the Drift database, not merely
/// onto the filesystem.
class LocalModelChoice {
  const LocalModelChoice({
    required this.id,
    required this.name,
    required this.fileName,
    required this.url,
    required this.approximateSize,
    required this.downloadMb,
    required this.ramMb,
    required this.minDeviceRamMb,
    required this.maxTokens,
    required this.contextBudgetChars,
    required this.note,
    required this.modelType,
    required this.fileType,
    this.minPhoneRamMb,
  });

  final String id;
  final String name;
  final String fileName;
  final String url;

  /// Prose for the user; cannot be compared against anything.
  final String approximateSize;

  /// The download in megabytes, for checking it will fit on disk. Measured from
  /// the actual file rather than rounded from [approximateSize].
  final int downloadMb;

  /// Rough resident cost of the weights, in megabytes.
  final int ramMb;

  /// Least device memory this is sensible on, in megabytes. Deliberately above
  /// [ramMb] — the OS, Flutter and the database are all resident too, and a
  /// model that just barely fits is one that gets the app killed under memory
  /// pressure.
  ///
  /// Compared against what the OS *reports*, which is materially less than what
  /// the device is sold as: a 4 GB Android reports about 3,967 MB, because the
  /// kernel reserves the rest. Thresholds written against marketing figures
  /// mis-fire immediately. Each is set roughly a tier below the nominal size it
  /// is meant to admit.
  final int minDeviceRamMb;

  final int maxTokens;
  final int contextBudgetChars;
  final String note;

  /// Which family the runtime should treat this as. Carried per model rather
  /// than fixed, because a single hardcoded `gemmaIt` would be wrong for every
  /// entry in a Qwen catalogue.
  final ModelType modelType;

  /// What a *phone* needs, or null if this model is desktop-only.
  ///
  /// Separate from [minDeviceRamMb] because the same number cannot serve both.
  /// A desktop may page and is limited by physical memory; iOS and Android cap
  /// what a single app may hold at well under the physical amount, and going
  /// over means the OS kills the app rather than swapping. So a 16 GB phone
  /// reports 16 GB and still cannot hold a 6 GB model, while a 16 GB laptop
  /// can.
  ///
  /// A ceiling, not a floor: the small models stay available everywhere, so a
  /// modest machine is offered the one that runs on it rather than being told
  /// nothing fits.
  final int? minPhoneRamMb;

  /// The container format, which decides which engine will accept the model.
  ///
  /// Explicit because both `installModel` and `createModel` default it to
  /// `ModelFileType.task`, and the engine registry matches on it exactly: with
  /// LiteRT-LM the only registered engine, a `.litertlm` file left declared as
  /// `task` downloads and installs perfectly and then fails at the first
  /// question with "No inference engine can handle this model".
  final ModelFileType fileType;

  Future<bool> isInstalled() async {
    try {
      return await FlutterGemma.isModelInstalled(fileName);
    } catch (_) {
      return false;
    }
  }

  /// Delete the downloaded weights.
  ///
  /// Half a gigabyte the user can no longer account for is not something to
  /// leave on a phone with no way to remove it, and "reinstall the app" is not
  /// an answer when doing so also discards their transactions and budgets.
  Future<void> uninstall() async {
    // Unloaded first: the runtime holds the file open, and on Windows deleting
    // it underneath a live handle fails outright rather than quietly.
    await _LocalModelRuntime.instance.unload();
    await FlutterGemma.uninstallModel(fileName);
  }

  /// Download and install, reporting progress 0-100.
  Stream<int> install() {
    final progress = StreamController<int>();
    () async {
      try {
        await FlutterGemma.installModel(
          modelType: modelType,
          fileType: fileType,
        ).fromNetwork(url).withProgress(progress.add).install();
        if (!progress.isClosed) progress.add(100);
      } catch (e) {
        if (!progress.isClosed) {
          progress.addError(InferenceException('Could not install $name: $e'));
        }
      } finally {
        await progress.close();
      }
    }();
    return progress.stream;
  }

  // ── Catalogue ──────────────────────────────────────────────────────────────
  //
  // Qwen 3 throughout, and deliberately so: it publishes at every size from
  // 0.6B to 8B under Apache-2.0 with no gate, so one family covers a phone and
  // a desktop workstation. Gemma was the obvious first choice and is unusable
  // here — the `litert-community` Gemma repositories are gated behind a
  // HuggingFace account and return HTTP 401 without a token, which is exactly
  // what this backend promises users they will not need. Embedding a shared
  // token in the app would be a credential in a client binary, one revocation
  // away from breaking for everyone.
  //
  // All `.litertlm`, the format LiteRT-LM reads, because LiteRT-LM is the only
  // engine covering desktop as well as phones. MediaPipe reads `.task` and is
  // Android and iOS only.

  static const LocalModelChoice qwen3_06b = LocalModelChoice(
    id: 'qwen3-0.6b',
    name: 'Qwen 3 0.6B',
    fileName: 'qwen3_0_6b_mixed_int4.litertlm',
    url: 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
        'qwen3_0_6b_mixed_int4.litertlm',
    approximateSize: '500 MB',
    downloadMb: 497,
    ramMb: 700,
    // Admits a nominal 3 GB phone, excludes a 2 GB one.
    minDeviceRamMb: 2600,
    minPhoneRamMb: 2600,
    maxTokens: 2048,
    contextBudgetChars: 3000,
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
    note: 'Small enough for any recent phone. Good at summarising and '
        'comparing your spending; a hosted model is still better for '
        'open-ended questions.',
  );

  static const LocalModelChoice qwen3_17b = LocalModelChoice(
    id: 'qwen3-1.7b',
    name: 'Qwen 3 1.7B',
    fileName: 'Qwen3_1.7B.litertlm',
    url: 'https://huggingface.co/litert-community/Qwen3-1.7B/resolve/main/'
        'Qwen3_1.7B.litertlm',
    approximateSize: '2.1 GB',
    downloadMb: 2056,
    ramMb: 2400,
    // Admits a nominal 6 GB desktop; on a phone it wants a nominal 12 GB,
    // because 2.4 GB resident has to fit inside a per-app cap rather than
    // inside physical memory.
    minDeviceRamMb: 5000,
    minPhoneRamMb: 11000,
    maxTokens: 2048,
    contextBudgetChars: 4000,
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
    note: 'Noticeably better reasoning than the 0.6B. Only worth it on a phone '
        'with plenty of memory to spare.',
  );

  static const LocalModelChoice qwen3_4b = LocalModelChoice(
    id: 'qwen3-4b-2507',
    name: 'Qwen 3 4B Instruct',
    fileName: 'qwen3_4b_instruct_2507_mixed_int4.litertlm',
    url: 'https://huggingface.co/litert-community/Qwen3-4B-Instruct-2507/'
        'resolve/main/qwen3_4b_instruct_2507_mixed_int4.litertlm',
    approximateSize: '2.7 GB',
    downloadMb: 2659,
    ramMb: 3200,
    // Desktop only: 3.2 GB resident is beyond what a phone will let one app
    // hold, whatever its physical memory says.
    minDeviceRamMb: 7000,
    maxTokens: 4096,
    contextBudgetChars: 6000,
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
    note: 'The best balance on a desktop. Handles a longer question and more '
        'of your history than the smaller two.',
  );

  static const LocalModelChoice qwen3_8b = LocalModelChoice(
    id: 'qwen3-8b',
    name: 'Qwen 3 8B',
    fileName: 'qwen3_8b_mixed_int4.litertlm',
    url: 'https://huggingface.co/litert-community/Qwen3-8B/resolve/main/'
        'qwen3_8b_mixed_int4.litertlm',
    approximateSize: '4.9 GB',
    downloadMb: 4887,
    ramMb: 6000,
    // Admits a nominal 16 GB machine. Desktop only, as above.
    minDeviceRamMb: 14000,
    maxTokens: 4096,
    contextBudgetChars: 8000,
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
    note: 'The most capable option, and the heaviest. For a machine with '
        'memory to spare, where it approaches what a hosted model gives you.',
  );

  /// Every model, for resolving a stored id whatever device wrote it.
  ///
  /// Someone who picked the 4B on a laptop and opens Settings on a phone must
  /// not hit a lookup failure; [byId] resolves against this and
  /// [recommendedHere] decides what is sensible on this device.
  static const List<LocalModelChoice> catalogue = [
    qwen3_06b,
    qwen3_17b,
    qwen3_4b,
    qwen3_8b,
  ];

  /// What to offer on this platform, smallest first.
  ///
  /// Split because the sizes that make sense differ by an order of magnitude: a
  /// 4.9 GB model is reasonable on a desktop and absurd on a phone, and a
  /// picker showing all four everywhere would mostly be offering downloads that
  /// cannot run.
  static List<LocalModelChoice> get all =>
      catalogue.where((m) => _isDesktop || m.minPhoneRamMb != null).toList();

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// [all], minus anything this device does not have the memory for.
  ///
  /// [all] is what the platform *could* run; this is what this machine can.
  /// Without it `minDeviceRamMb` is decoration and a 2 GB phone gets offered a
  /// 2.1 GB model, which downloads in full and is then killed by the OS.
  ///
  /// Never returns empty. If nothing fits, the smallest is offered anyway with
  /// [fitsThisDevice] false, so the screen can say plainly that it is more than
  /// the device has rather than hiding the feature and explaining nothing.
  static Future<List<LocalModelChoice>> availableHere() async {
    final total = await DeviceMemory.totalMb();
    if (total == null) return all;
    final fits = all.where((m) => total >= m.requiredMb).toList();
    return fits.isEmpty ? [all.first] : fits;
  }

  /// What this model asks for on the platform it is running on.
  int get requiredMb =>
      LocalModelChoice._isDesktop ? minDeviceRamMb : (minPhoneRamMb ?? 1 << 30);

  /// Whether this device has the memory this model asks for. Permissive when
  /// the amount cannot be read — see [DeviceMemory.totalMb].
  Future<bool> fitsThisDevice() => DeviceMemory.meets(requiredMb);

  /// Whether this model's download will fit in the space left on the device.
  Future<bool> fitsOnDisk() => DeviceStorage.hasRoomFor(downloadMb);

  /// Resolved against the whole catalogue, not the platform's shortlist, so a
  /// choice made on another device is recognised rather than silently reset.
  static LocalModelChoice byId(String id) => catalogue.firstWhere(
        (m) => m.id == id,
        orElse: fallback,
      );

  /// Whether a downloaded model can run on this platform at all.
  ///
  /// Every platform Sats Stack targets, now that LiteRT-LM is the engine. The
  /// architecture caveats are LiteRT-LM's: macOS on Apple silicon (not Intel),
  /// Windows x64 (not arm64), Linux on both.
  static bool get runsHere =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux;

  /// The two or three models worth putting in front of this user.
  ///
  /// Everything that fits is not a useful list — on a workstation that is four
  /// entries differing by an order of magnitude in both download size and
  /// speed, with nothing to say which is which. These are the three questions
  /// someone actually has: what is the sensible choice, what if I want it
  /// smaller and faster, and what if I want the best answers this machine can
  /// give.
  ///
  /// [LocalModelTier.recommended] is deliberately *not* the largest that fits
  /// once there are three or more. The largest is the slowest, and picking it
  /// by default would make the feature feel broken on the very machines that
  /// can run the most; it is offered as [LocalModelTier.large] instead, plainly
  /// described as slower.
  static Future<List<({LocalModelTier tier, LocalModelChoice model})>>
      tiersHere() async {
    final fits = await availableHere();
    if (fits.length == 1) {
      return [(tier: LocalModelTier.recommended, model: fits.first)];
    }
    if (fits.length == 2) {
      return [
        (tier: LocalModelTier.small, model: fits.first),
        (tier: LocalModelTier.recommended, model: fits.last),
      ];
    }
    return [
      (tier: LocalModelTier.small, model: fits.first),
      (tier: LocalModelTier.recommended, model: fits[fits.length - 2]),
      (tier: LocalModelTier.large, model: fits.last),
    ];
  }

  /// The most capable model this device can actually hold.
  ///
  /// Defined as whatever the picker labels [LocalModelTier.recommended], so the
  /// model selected by default and the row marked "Recommended" can never
  /// disagree.
  static Future<LocalModelChoice> recommendedHere() async {
    final tiers = await tiersHere();
    return tiers.firstWhere((t) => t.tier == LocalModelTier.recommended).model;
  }

  /// The conservative default, for the moment before memory has been read.
  ///
  /// Something is needed synchronously at construction and the memory probe is
  /// asynchronous, so this is the smallest — being briefly under-ambitious
  /// costs nothing, while briefly claiming a model the device cannot hold would
  /// show a download that should not be started. Replaced by [recommendedHere]
  /// as soon as settings load.
  static LocalModelChoice fallback() => all.first;
}
