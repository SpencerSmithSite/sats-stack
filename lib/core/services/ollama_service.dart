import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;

import '../../shared/constants/app_constants.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/platform_utils.dart';
import '../../shared/utils/sat_converter.dart';
import '../../shared/utils/url_utils.dart';
import '../database/database.dart';
import '../models/ai_provider.dart';
import 'inference/cloud_backend.dart';
import 'inference/gemini_nano_backend.dart';
import 'inference/inference_backend.dart';
import 'inference/platform_llm_backend.dart';
import 'inference/remote_backends.dart';
import 'secure_key_store.dart';

/// Owns the user's AI configuration and hands out the selected backend.
///
/// Named for Ollama because that was the only option when it was written; it is
/// now a facade over `inference/`, where each backend implements
/// [InferenceBackend]. The class keeps its old surface — [chat], [isAvailable],
/// [listModels] — so the chat and import screens did not have to change, but
/// each of those now delegates to whichever backend is selected rather than
/// switching on a provider enum.
class OllamaService {
  OllamaService(this._db, {SecureKeyStore keyStore = const SecureKeyStore()})
    : _keyStore = keyStore;

  final AppDatabase _db;

  /// Where API keys live. Injectable so tests can substitute a store that does
  /// not need a platform keychain.
  final SecureKeyStore _keyStore;

  // ── Ollama fields ─────────────────────────────────────────────────────────

  String _baseUrl = AppConstants.defaultOllamaUrl;
  String? _selectedModel;
  bool _isConnected = false;

  // ── LM Studio fields ──────────────────────────────────────────────────────

  String _lmStudioBaseUrl = AppConstants.defaultLmStudioUrl;
  String? _lmStudioSelectedModel;
  bool _lmStudioConnected = false;

  // ── Maple fields ──────────────────────────────────────────────────────────

  String _mapleBaseUrl = AppConstants.defaultMapleUrl;
  String? _mapleSelectedModel;
  String _mapleApiKey = '';
  bool _mapleConnected = false;

  /// The keychain entry name Maple's key uses. Not a [CloudProvider] — Maple is
  /// configured like a server, with its own URL — but its key is a credential
  /// like any other and belongs in the same store.
  static const String _mapleKeyId = 'maple';

  // ── Hosted provider fields ────────────────────────────────────────────────

  /// Per-provider model, key and last verified connection state, keyed by
  /// [CloudProvider.id].
  ///
  /// Maps rather than four sets of fields: the four providers differ only in
  /// their wire format, which `CloudBackend` owns, so duplicating the storage
  /// four times would only create four places to forget to update.
  final Map<String, String> _cloudModels = {};
  final Map<String, String> _cloudKeys = {};
  final Map<String, bool> _cloudConnected = {};

  // ── Active provider ───────────────────────────────────────────────────────

  AiProvider _activeProvider = AiProvider.ollama;

  // ── Public getters ────────────────────────────────────────────────────────

  AiProvider get activeProvider => _activeProvider;

  /// The backend for the current selection, constructed fresh each time so a
  /// configuration edit takes effect without anything having to invalidate a
  /// cached instance.
  InferenceBackend get backend => switch (_activeProvider) {
    AiProvider.ollama => OllamaBackend(
      baseUrl: _baseUrl,
      model: _selectedModel,
      isPrivate: isLocalEndpoint(_baseUrl),
    ),
    AiProvider.lmStudio => OpenAiCompatBackend(
      id: OpenAiCompatBackend.lmStudioId,
      displayName: 'LM Studio',
      description:
          isLocalEndpoint(_lmStudioBaseUrl)
              ? 'A model running in LM Studio on this machine. Nothing '
                  'leaves your device.'
              : 'LM Studio on the server you configured. Your financial '
                  'figures are sent there to answer each question.',
      baseUrl: _lmStudioBaseUrl,
      model: _lmStudioSelectedModel,
      apiKey: '',
      // Derived from the URL, not hardcoded. The field is free text, so
      // "Nothing leaves your device" was a claim the app could not back:
      // a user pointing it at a VPS got the reassurance anyway, and this
      // flag now decides whether insights generate automatically and
      // whether statements are uploaded without asking.
      isPrivate: isLocalEndpoint(_lmStudioBaseUrl),
      contextBudgetChars: 12000,
    ),
    AiProvider.maple => OpenAiCompatBackend(
      id: OpenAiCompatBackend.mapleId,
      displayName: 'Maple',
      description:
          'A hosted model. Your financial figures are sent to the server '
          'to answer each question.',
      baseUrl: _mapleBaseUrl,
      model: _mapleSelectedModel,
      apiKey: _mapleApiKey,
      // Hosted, so the privacy disclosure has to say so — this is the one
      // backend where the app's "nothing leaves your device" claim does
      // not hold, and the picker must not let it stand unqualified.
      isPrivate: false,
      contextBudgetChars: 24000,
    ),
    AiProvider.appleIntelligence => const PlatformLlmBackend(),
    AiProvider.geminiNano => const GeminiNanoBackend(),
    AiProvider.claude ||
    AiProvider.chatGpt ||
    AiProvider.gemini ||
    AiProvider.grok => cloudBackendFor(_activeProvider.cloudProvider!),
  };

  /// The backend for a hosted provider, whether or not it is the active one.
  ///
  /// Settings needs this to fetch a model list for a provider the user is
  /// configuring but has not switched to yet.
  CloudBackend cloudBackendFor(CloudProvider provider) => CloudBackend(
    provider: provider,
    model: cloudModel(provider),
    apiKey: cloudApiKey(provider),
  );

  /// The chosen model for a hosted provider, falling back to its default.
  String cloudModel(CloudProvider provider) =>
      _cloudModels[provider.id] ?? provider.defaultModel;

  /// The saved API key for a hosted provider, or an empty string.
  String cloudApiKey(CloudProvider provider) => _cloudKeys[provider.id] ?? '';

  /// Whether a hosted provider's key was accepted the last time it was checked.
  bool cloudConnected(CloudProvider provider) =>
      _cloudConnected[provider.id] ?? false;

  /// How much financial context the active backend can usefully take.
  ///
  /// Exposed so the system prompt builder can size what it sends. Apple's model
  /// and Gemini Nano take roughly a third of what a hosted model does, and
  /// overfilling them degrades the answer rather than erroring.
  int get contextBudgetChars => backend.contextBudgetChars;

  /// Whether the active backend keeps everything on this device.
  bool get sendsDataOffDevice => !backend.isPrivate;

  /// Who receives the user's figures when [sendsDataOffDevice] is true, phrased
  /// for a sentence. Null when nothing leaves.
  ///
  /// `AiProvider.dataRecipient` covers the hosted providers, which have a fixed
  /// endpoint. Ollama and LM Studio do not: their URL is whatever the user
  /// typed, so the recipient is that host — known only here.
  String? get activeDataRecipient =>
      recipientFor(_activeProvider, _activeServerUrl ?? '');

  /// Who receives the user's figures if [provider] is used with [url] (its
  /// server, for the providers whose server the user chooses), phrased for a
  /// sentence; null when nothing leaves hardware the user controls.
  ///
  /// Static so onboarding can judge a URL that is still being typed, rather
  /// than the provider alone: `AiProvider.isPrivate` is true for Ollama and
  /// LM Studio, whose URL can point anywhere.
  static String? recipientFor(AiProvider provider, String url) {
    String? host() {
      final h = Uri.tryParse(normalizeServerUrl(url) ?? url)?.host;
      return h == null || h.isEmpty ? null : h;
    }

    switch (provider) {
      case AiProvider.maple:
        // Hosted, but at whatever URL the user typed: name the host too.
        final h = host();
        return h == null
            ? provider.dataRecipient
            : '${provider.dataRecipient} ($h)';
      case AiProvider.ollama:
      case AiProvider.lmStudio:
        if (isLocalEndpoint(
          normalizeServerUrl(url, defaultScheme: 'http') ?? url,
        )) {
          return null;
        }
        final h = host();
        return h == null
            ? 'the server you configured'
            : 'the server you configured ($h)';
      default:
        return provider.dataRecipient;
    }
  }

  /// What the user should know about how [url] is reached, or null when
  /// there is nothing to say.
  ///
  /// [recipientFor] treats a server on the local network as the user's own
  /// hardware, so no off-device banner or consent prompt shows for it: someone
  /// who runs their own AI server knows where it is (decided 2026-10-31). The
  /// note still says the figures cross the network — the old copy said
  /// "nothing leaves", which is not what happens — but as a plain fact, not a
  /// warning. A remote server over plain `http://` is warned about: everything
  /// sent to it travels readable.
  static String? transportNoteFor(AiProvider provider, String url) {
    if (provider != AiProvider.ollama &&
        provider != AiProvider.lmStudio &&
        provider != AiProvider.maple) {
      return null;
    }
    final normalized =
        normalizeServerUrl(url, defaultScheme: 'http') ?? url.trim();
    if (normalized.isEmpty || isLoopbackEndpoint(normalized)) return null;
    final uri = Uri.tryParse(normalized);
    final host = uri?.host ?? '';
    if (host.isEmpty) return null;
    if (isLocalEndpoint(normalized)) {
      return 'Sent over your local network to $host, and no further.';
    }
    if (uri!.scheme == 'http') {
      return 'Sent unencrypted (http://), so anything between here and $host '
          'can read it. Use https:// for a server outside your network.';
    }
    return null;
  }

  /// Whether [url] is this device itself — the only case where nothing
  /// crosses a network at all.
  static bool isLoopbackEndpoint(String url) {
    if (url.trim().isEmpty) return true;
    final host = Uri.tryParse(url.trim())?.host ?? '';
    return host == 'localhost' ||
        host == '::1' ||
        host == '0.0.0.0' ||
        host.endsWith('.localhost') ||
        RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
  }

  /// The URL the active provider sends to, for the providers whose endpoint
  /// is the user's to choose; null for the rest.
  String? get _activeServerUrl => switch (_activeProvider) {
    AiProvider.ollama => _baseUrl,
    AiProvider.lmStudio => _lmStudioBaseUrl,
    AiProvider.maple => _mapleBaseUrl,
    _ => null,
  };

  /// What a consent to send data off the device was given *to*.
  ///
  /// For a hosted provider with a fixed endpoint, the provider is enough. For
  /// Ollama, LM Studio and Maple it is the server: consent given for one host
  /// must not carry over when the URL is changed to another, which it did
  /// while consent was stored per provider.
  String get activeConsentScope {
    final url = _activeServerUrl;
    if (url == null) return 'hosted';
    final uri = Uri.tryParse(url);
    return uri == null || uri.host.isEmpty
        ? url
        : '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  /// Whether [url] is this device or a machine on the user's own network.
  ///
  /// Loopback, `.local`, link-local and the RFC 1918 private ranges count:
  /// those are hardware the user controls, so "nothing leaves your device" is
  /// close enough to true to say. A public hostname is not, however much the
  /// user trusts the box — it crosses the internet to get there.
  ///
  /// Fails **closed**: anything that is not blank and yields no host is
  /// treated as remote. It used to fail open, so `ollama.example.com:11434` —
  /// which `Uri` reads as a *scheme* with no host — was called local: no
  /// consent prompt on import, auto-insight on, and a false privacy claim.
  /// The setters below normalise on save so that input now gets a host; this
  /// is the backstop for a value that still cannot be parsed.
  static bool isLocalEndpoint(String url) {
    // Blank means the field is unset and a localhost default is in force.
    if (url.trim().isEmpty) return true;
    final host = Uri.tryParse(url.trim())?.host ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        host == '::1' ||
        host.endsWith('.local') ||
        host.endsWith('.localhost')) {
      return true;
    }
    final v4 = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(host);
    if (v4 == null) return false;
    final a = int.parse(v4.group(1)!);
    final b = int.parse(v4.group(2)!);
    if (a == 127 || a == 10) return true; // loopback, private
    if (a == 0) return true; // 0.0.0.0
    if (a == 192 && b == 168) return true; // private
    if (a == 172 && b >= 16 && b <= 31) return true; // private
    if (a == 169 && b == 254) return true; // link-local
    return false;
  }

  /// Base URL of the Ollama server (used for Ollama-specific settings UI).
  String get baseUrl => _baseUrl;

  String get lmStudioBaseUrl => _lmStudioBaseUrl;
  String get mapleBaseUrl => _mapleBaseUrl;
  String get mapleApiKey => _mapleApiKey;

  /// Model selected for the currently active provider.
  ///
  /// Null for Apple Intelligence and Gemini Nano: each ships exactly one model
  /// that the OS owns and does not name, so there is nothing for a model picker
  /// to show.
  String? get selectedModel => switch (_activeProvider) {
    AiProvider.ollama => _selectedModel,
    AiProvider.lmStudio => _lmStudioSelectedModel,
    AiProvider.maple => _mapleSelectedModel,
    AiProvider.appleIntelligence || AiProvider.geminiNano => null,
    AiProvider.claude ||
    AiProvider.chatGpt ||
    AiProvider.gemini ||
    AiProvider.grok => cloudModel(_activeProvider.cloudProvider!),
  };

  // Per-provider model getters (used by settings screen to show all providers).
  String? get ollamaSelectedModel => _selectedModel;
  String? get lmStudioSelectedModel => _lmStudioSelectedModel;
  String? get mapleSelectedModel => _mapleSelectedModel;

  /// Whether the active backend is ready to answer.
  ///
  /// For the server-backed providers this is a persisted flag, set the last
  /// time a connection was verified. For the on-device backends "connected" is
  /// the wrong idea — there is no host — so it reflects the last availability
  /// report from the OS, refreshed by [refreshOnDeviceReadiness]. Defaults to
  /// false until that first check completes, so nothing claims readiness it has
  /// not confirmed.
  bool get isConnected => switch (_activeProvider) {
    AiProvider.ollama => _isConnected,
    AiProvider.lmStudio => _lmStudioConnected,
    AiProvider.maple => _mapleConnected,
    AiProvider.appleIntelligence || AiProvider.geminiNano => _onDeviceReady,
    AiProvider.claude ||
    AiProvider.chatGpt ||
    AiProvider.gemini ||
    AiProvider.grok => cloudConnected(_activeProvider.cloudProvider!),
  };

  /// Whether the AI tab should be visible with [provider] selected.
  ///
  /// The one rule, so the three places that decide this cannot disagree again.
  /// Settings omitted the hosted-provider term that onboarding had, so a
  /// mobile user with a saved Anthropic key lost the AI tab by switching
  /// provider and back; and main.dart seeded the notifier from
  /// `isDesktop || isConnected`, where an on-device provider's `isConnected`
  /// is a probe that `loadSettings` only kicks off, so on-device providers
  /// lost the tab after every restart.
  bool aiShouldBeEnabled(AiProvider provider) =>
      PlatformUtils.isDesktop || isUsableWithoutDesktop(provider);

  /// Whether [provider] can answer on a device that is not a desktop.
  ///
  /// Split out from [aiShouldBeEnabled] so the rule itself is testable without
  /// pretending to be a phone.
  bool isUsableWithoutDesktop(AiProvider provider) {
    return switch (provider) {
      // There is no host to reach. Readiness is the OS's answer, re-asked on
      // every launch, so the tab must not wait on a probe that has not
      // returned — the AI screen reports an unavailable backend itself.
      AiProvider.appleIntelligence || AiProvider.geminiNano => true,
      // A key is all a hosted provider needs: no local server is involved, so
      // the tab belongs on a phone.
      AiProvider.claude ||
      AiProvider.chatGpt ||
      AiProvider.gemini ||
      AiProvider.grok => cloudApiKey(provider.cloudProvider!).isNotEmpty,
      // A server-backed provider needs a host that answered.
      AiProvider.ollama => _isConnected,
      AiProvider.lmStudio => _lmStudioConnected,
      AiProvider.maple => _mapleConnected,
    };
  }

  /// [aiShouldBeEnabled] for the provider that is actually selected.
  bool get aiEnabled => aiShouldBeEnabled(_activeProvider);

  bool _onDeviceReady = false;

  /// Re-ask the active on-device backend whether it can answer.
  ///
  /// Separate from [setConnected] because nothing here is persisted: the answer
  /// can change between launches without the app doing anything — the user
  /// turns Apple Intelligence on, AICore finishes a download, someone deletes
  /// the downloaded weights — so it is always read fresh rather than trusted
  /// from disk.
  Future<bool> refreshOnDeviceReadiness() async {
    if (!_activeProvider.isOnDevice) return isConnected;
    _onDeviceReady = (await backend.checkStatus()).available;
    return _onDeviceReady;
  }

  // ── Config (persisted in AppSettings) ────────────────────────────────────

  Future<void> loadSettings() async {
    final rows = await _db.select(_db.appSettings).get();
    final map = {for (final r in rows) r.key: r.value};

    // Ollama
    _baseUrl = _serverUrl(
      map[AppConstants.settingOllamaUrl],
      AppConstants.defaultOllamaUrl,
    );
    _selectedModel = map[AppConstants.settingOllamaModel];
    _isConnected = map[AppConstants.settingOllamaConnected] == 'true';

    // LM Studio
    _lmStudioBaseUrl = _serverUrl(
      map[AppConstants.settingLmStudioUrl],
      AppConstants.defaultLmStudioUrl,
    );
    _lmStudioSelectedModel = map[AppConstants.settingLmStudioModel];
    _lmStudioConnected = map[AppConstants.settingLmStudioConnected] == 'true';

    // Maple
    _mapleBaseUrl = _serverUrl(
      map[AppConstants.settingMapleUrl],
      AppConstants.defaultMapleUrl,
      scheme: 'https',
    );
    _mapleSelectedModel = map[AppConstants.settingMapleModel];
    _mapleConnected = map[AppConstants.settingMapleConnected] == 'true';
    _mapleApiKey = await _keyStore.read(_mapleKeyId);

    // Hosted providers. Models and connection state come from settings; the
    // keys come from the keychain.
    for (final p in CloudProvider.values) {
      final model = map[AppConstants.cloudModelKey(p.id)];
      if (model != null && model.isNotEmpty) _cloudModels[p.id] = model;
      _cloudConnected[p.id] =
          map[AppConstants.cloudConnectedKey(p.id)] == 'true';
      _cloudKeys[p.id] = await _keyStore.read(p.id);
    }

    await _migrateMapleKeyToKeychain(map);
    await _refileKeysUnderDeviceOnlyClass(map);

    // Active provider
    var providerKey = map[AppConstants.settingAiProvider];
    if (providerKey == AiProvider.removedLocalModelKey) {
      // The downloadable-model backend is gone. Someone who chose it chose an
      // on-device model, so they move to the platform's built-in one rather
      // than falling back to Ollama — which on a phone means no AI tab at all
      // — and certainly not to anything hosted. If it is unavailable, the
      // status panel says why and what to do.
      final replacement = replacementForRemovedLocalModel(
        appleBridged: PlatformLlmBackend.bridgedHere,
        androidBridged: GeminiNanoBackend.bridgedHere,
      );
      providerKey = replacement.key;
      await _upsertSetting(AppConstants.settingAiProvider, providerKey);
    }
    _activeProvider = AiProvider.fromKey(providerKey);
    if (map.containsKey(AppConstants.settingRemovedLocalModelId)) {
      await (_db.delete(_db.appSettings)..where(
        (t) => t.key.equals(AppConstants.settingRemovedLocalModelId),
      )).go();
    }

    // Availability is never read from disk — see [refreshOnDeviceReadiness].
    if (_activeProvider.isOnDevice) {
      unawaited(refreshOnDeviceReadiness());
    }
  }

  /// Move a Maple key written by an earlier build out of the settings table.
  ///
  /// Earlier builds stored it as plaintext in `AppSettings`, which Settings →
  /// Data exports wholesale. Migrating on load rather than in a schema
  /// migration because the destination is the keychain, not another table — a
  /// Drift migration cannot reach it, and this has to survive a restore from a
  /// backup taken before the move.
  ///
  /// The row is deleted only after the keychain write is confirmed. If the
  /// keychain is unavailable the plaintext value is left where it is and kept
  /// in memory, so the user's Maple setup keeps working and the migration
  /// simply retries next launch. Deleting first would lose the key outright.
  Future<void> _migrateMapleKeyToKeychain(Map<String, String> settings) async {
    final legacy = settings[AppConstants.settingMapleApiKey];
    if (legacy == null || legacy.isEmpty) return;

    if (_mapleApiKey.isEmpty) {
      final stored = await _keyStore.write(_mapleKeyId, legacy);
      if (!stored) {
        _mapleApiKey = legacy;
        return;
      }
      _mapleApiKey = legacy;
    }

    await (_db.delete(_db.appSettings)
      ..where((t) => t.key.equals(AppConstants.settingMapleApiKey))).go();
  }

  /// The URL to use for a server field the user typed into.
  ///
  /// Blank is the default. A bare `host:port` gets [scheme] — http for Ollama
  /// and LM Studio, which serve plain HTTP out of the box. Anything that still
  /// cannot be read is kept as typed, so the user sees their own input and the
  /// connection test fails on it, while [isLocalEndpoint] treats it as remote.
  static String _serverUrl(
    String? raw,
    String fallback, {
    String scheme = 'http',
  }) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    return normalizeServerUrl(raw, defaultScheme: scheme) ?? raw.trim();
  }

  /// Where a stored choice of the removed downloadable-model backend moves to:
  /// the platform's own on-device model, or Ollama where there is none.
  static AiProvider replacementForRemovedLocalModel({
    required bool appleBridged,
    required bool androidBridged,
  }) {
    if (appleBridged) return AiProvider.appleIntelligence;
    if (androidBridged) return AiProvider.geminiNano;
    return AiProvider.ollama;
  }

  /// Persist Ollama settings (URL and/or model).
  Future<void> saveSettings({String? url, String? model}) async {
    if (url != null) {
      _baseUrl = _serverUrl(url, AppConstants.defaultOllamaUrl);
      await _upsertSetting(AppConstants.settingOllamaUrl, _baseUrl);
    }
    if (model != null) {
      _selectedModel = model;
      await _upsertSetting(AppConstants.settingOllamaModel, model);
    }
  }

  /// Persist LM Studio settings.
  Future<void> saveLmStudioSettings({String? url, String? model}) async {
    if (url != null) {
      _lmStudioBaseUrl = _serverUrl(url, AppConstants.defaultLmStudioUrl);
      await _upsertSetting(AppConstants.settingLmStudioUrl, _lmStudioBaseUrl);
    }
    if (model != null) {
      _lmStudioSelectedModel = model;
      await _upsertSetting(AppConstants.settingLmStudioModel, model);
    }
  }

  /// Persist Maple settings.
  ///
  /// Returns false if an API key was supplied and the keychain refused it —
  /// the caller should tell the user rather than letting a key that will not
  /// survive the next launch look saved.
  Future<bool> saveMapleSettings({
    String? url,
    String? model,
    String? apiKey,
  }) async {
    if (url != null) {
      _mapleBaseUrl = _serverUrl(
        url,
        AppConstants.defaultMapleUrl,
        scheme: 'https',
      );
      await _upsertSetting(AppConstants.settingMapleUrl, _mapleBaseUrl);
    }
    if (model != null) {
      _mapleSelectedModel = model;
      await _upsertSetting(AppConstants.settingMapleModel, model);
    }
    if (apiKey != null) {
      _mapleApiKey = apiKey;
      final ok = await _keyStore.write(_mapleKeyId, apiKey);
      configChanges.value++;
      return ok;
    }
    return true;
  }

  /// Persist a hosted provider's model and/or API key.
  ///
  /// Returns false if an API key was supplied and the keychain refused it. The
  /// value is still held in memory so the session keeps working, but it will
  /// not be there next launch and the user needs to know that.
  Future<bool> saveCloudSettings(
    CloudProvider provider, {
    String? model,
    String? apiKey,
  }) async {
    if (model != null && model.isNotEmpty) {
      _cloudModels[provider.id] = model;
      await _upsertSetting(AppConstants.cloudModelKey(provider.id), model);
    }
    if (apiKey != null) {
      final trimmed = apiKey.trim();
      _cloudKeys[provider.id] = trimmed;
      // A key that changed invalidates whatever the last check concluded.
      _cloudConnected[provider.id] = false;
      await _upsertSetting(
        AppConstants.cloudConnectedKey(provider.id),
        'false',
      );
      final ok = await _keyStore.write(provider.id, trimmed);
      configChanges.value++;
      return ok;
    }
    return true;
  }

  /// Forget every stored API key. Called by Settings → Danger Zone → Reset all
  /// data, where credentials surviving a reset would be a surprise.
  Future<void> clearAllApiKeys() async {
    for (final p in CloudProvider.values) {
      await _keyStore.delete(p.id);
      _cloudKeys[p.id] = '';
      _cloudConnected[p.id] = false;
    }
    await _keyStore.delete(_mapleKeyId);
    _mapleApiKey = '';
    // The Bitcoin Core RPC password lives in the same keychain; a reset that
    // left it behind would not be a reset.
    await _keyStore.deleteEntry(AppConstants.settingBitcoinRpcPassword);
    // Nothing else is written, so nothing else would tell the screens that
    // read the keys.
    configChanges.value++;
  }

  /// Save the model for whichever provider is currently active.
  ///
  /// A no-op for the platform backends: neither lets the app choose a model, so
  /// there is nothing to write. Silently ignoring is right here — the callers
  /// are model pickers that are not shown for those backends at all.
  Future<void> saveModelForActiveProvider(String model) async {
    switch (_activeProvider) {
      case AiProvider.ollama:
        await saveSettings(model: model);
      case AiProvider.lmStudio:
        await saveLmStudioSettings(model: model);
      case AiProvider.maple:
        await saveMapleSettings(model: model);
      case AiProvider.claude:
      case AiProvider.chatGpt:
      case AiProvider.gemini:
      case AiProvider.grok:
        await saveCloudSettings(_activeProvider.cloudProvider!, model: model);
      case AiProvider.appleIntelligence:
      case AiProvider.geminiNano:
        break;
    }
  }

  /// Persist the active provider selection.
  Future<void> setActiveProvider(AiProvider provider) async {
    _activeProvider = provider;
    await _upsertSetting(AppConstants.settingAiProvider, provider.key);
    // A newly-selected on-device backend has no persisted readiness to fall
    // back on, and the stale value belongs to the previous backend.
    _onDeviceReady = false;
    if (provider.isOnDevice) await refreshOnDeviceReadiness();
  }

  /// Mark the currently active provider as connected/disconnected.
  Future<void> setConnected(bool value) async {
    switch (_activeProvider) {
      case AiProvider.ollama:
        _isConnected = value;
        await _upsertSetting(
          AppConstants.settingOllamaConnected,
          value.toString(),
        );
      case AiProvider.lmStudio:
        _lmStudioConnected = value;
        await _upsertSetting(
          AppConstants.settingLmStudioConnected,
          value.toString(),
        );
      case AiProvider.maple:
        _mapleConnected = value;
        await _upsertSetting(
          AppConstants.settingMapleConnected,
          value.toString(),
        );
      case AiProvider.claude:
      case AiProvider.chatGpt:
      case AiProvider.gemini:
      case AiProvider.grok:
        final p = _activeProvider.cloudProvider!;
        _cloudConnected[p.id] = value;
        await _upsertSetting(
          AppConstants.cloudConnectedKey(p.id),
          value.toString(),
        );
      case AiProvider.appleIntelligence:
      case AiProvider.geminiNano:
        // Not persisted — the OS owns this answer and it can change between
        // launches without the app doing anything.
        _onDeviceReady = value;
    }
  }

  /// Rewrites each stored key once, so it moves to the keychain class
  /// `SecureKeyStore` now asks for — see the comment there. Recorded in
  /// settings, so it runs once per install.
  Future<void> _refileKeysUnderDeviceOnlyClass(Map<String, String> map) async {
    if (map[AppConstants.settingKeysDeviceOnly] == 'true') return;
    var ok = true;
    for (final p in CloudProvider.values) {
      final key = _cloudKeys[p.id] ?? '';
      if (key.isNotEmpty) ok &= await _keyStore.write(p.id, key);
    }
    if (_mapleApiKey.isNotEmpty) {
      ok &= await _keyStore.write(_mapleKeyId, _mapleApiKey);
    }
    // Tried again next launch if the keychain refused a write.
    if (ok) await _upsertSetting(AppConstants.settingKeysDeviceOnly, 'true');
  }

  Future<void> _upsertSetting(String key, String value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
    configChanges.value++;
  }

  /// Bumped after any AI configuration is written — provider, endpoint, key,
  /// connection state, model.
  ///
  /// The AI tab used to be rebuilt from scratch on every tab switch, which
  /// incidentally re-read its configuration each visit. Tabs now stay alive
  /// (see app.dart), so a screen that loaded configuration once has to be told
  /// when it changes — otherwise fixing an Ollama URL in Settings and returning
  /// to the chat would leave it reporting the old URL as unreachable.
  final ValueNotifier<int> configChanges = ValueNotifier(0);

  /// The parts of the configuration a chat session depends on: which backend,
  /// where it lives, and whether it has a key. Deliberately *not* the selected
  /// model — the chat reads that live, and including it would make picking a
  /// model from the chat's own dropdown trigger a reload of the chat.
  String get configFingerprint => [
    _activeProvider.key,
    _baseUrl,
    _lmStudioBaseUrl,
    _mapleBaseUrl,
    _mapleApiKey.isNotEmpty,
    for (final id in _cloudKeys.keys.toList()..sort())
      '$id:${_cloudKeys[id]!.isNotEmpty}',
  ].join('|');

  // ── Connectivity ──────────────────────────────────────────────────────────

  /// Whether the active backend can answer right now.
  ///
  /// Delegates rather than switching: "reachable" means a reachable host for
  /// Ollama, a valid key for a hosted model, and something else entirely for
  /// the on-device backends — supported hardware, a setting switched on, or
  /// weights present. Each backend is the only thing that knows which.
  Future<bool> isAvailable() async => (await checkStatus()).available;

  /// The same check, keeping the reason. Prefer this where the UI has room to
  /// say what is wrong: "Apple Intelligence is switched off. Turn it on in
  /// Settings" is actionable in a way that a greyed-out row is not.
  ///
  /// A self-hosted server with no model chosen yet gets one: the first it
  /// lists. Ollama, LM Studio and Maple report "unavailable" without a model,
  /// and every caller listed models only once the backend was available — so
  /// a first-time setup could never pass its connection test, never list a
  /// model, and so never get one.
  Future<BackendStatus> checkStatus() async {
    if (_activeProvider.defaultUrl != null &&
        (selectedModel?.isEmpty ?? true)) {
      final models = await backend.availableModels();
      if (models.isNotEmpty) await saveModelForActiveProvider(models.first);
    }
    return lastStatus = await backend.checkStatus();
  }

  /// What the most recent [checkStatus] or [isAvailable] found, so a screen
  /// that only asked yes or no can still say why not.
  BackendStatus? lastStatus;

  // ── Models ────────────────────────────────────────────────────────────────

  /// Lists available models for the currently active provider.
  ///
  /// Empty for Apple Intelligence and Gemini Nano — each ships one model the OS
  /// owns. Callers should treat an empty list as "no choice to make" rather
  /// than as a failure to fetch.
  Future<List<String>> listModels() => backend.availableModels();

  // ── System prompt ─────────────────────────────────────────────────────────

  /// Builds the system prompt, sized to what the active backend can take.
  ///
  /// [budgetChars] defaults to the selected backend's [contextBudgetChars],
  /// which varies by an order of magnitude — roughly 3–4k for Apple
  /// Intelligence, Gemini Nano and the smallest downloaded model, against 24k
  /// for a hosted one. Overfilling a small window degrades the answer rather
  /// than erroring, so this sends *fewer* spending categories on those backends
  /// rather than a truncated ledger.
  ///
  /// The framing and the headline figures are always included: a prompt missing
  /// the user's actual numbers is useless at any size, and together they are
  /// well under even the smallest budget. Only the category list flexes, and it
  /// is built up line by line so the result is a whole number of categories
  /// rather than a sentence cut mid-word.
  ///
  /// Pass [budgetChars] explicitly only to test the sizing, or to build a
  /// prompt for a backend other than the active one.
  String buildSystemPrompt({
    required int totalStackSats,
    required double? btcPrice,
    required String currency,
    required DateTime month,
    required double monthlyIncome,
    required double monthlySpending,
    required double monthlySurplus,
    required Map<String, double> spendingByCategory,
    int? stackGoalSats,
    int? budgetChars,
  }) => composeSystemPrompt(
    totalStackSats: totalStackSats,
    btcPrice: btcPrice,
    currency: currency,
    month: month,
    monthlyIncome: monthlyIncome,
    monthlySpending: monthlySpending,
    monthlySurplus: monthlySurplus,
    spendingByCategory: spendingByCategory,
    stackGoalSats: stackGoalSats,
    budgetChars: budgetChars ?? contextBudgetChars,
  );

  /// The prompt builder itself — a pure function of its inputs.
  ///
  /// Static because it needs nothing from the service but the budget, and
  /// because `OllamaService` requires an `AppDatabase`, which cannot be
  /// constructed under `flutter test`. Keeping the logic here means the sizing
  /// rules are testable without a database or a device.
  ///
  /// Every figure is in [currency], the one the dashboard aggregated into, and
  /// is labelled with it. The prompt used to print a `$` and "USD" whatever
  /// the user's currency, round each figure to a whole unit, report a missing
  /// price as "$0", and not say which month the figures were for — so a GBP
  /// user was answered in dollars, with sats worked out from nonsense.
  static String composeSystemPrompt({
    required int totalStackSats,
    required double? btcPrice,
    required String currency,
    required DateTime month,
    required double monthlyIncome,
    required double monthlySpending,
    required double monthlySurplus,
    required Map<String, double> spendingByCategory,
    required int budgetChars,
    int? stackGoalSats,
    DateTime? now,
  }) {
    final budget = budgetChars;
    final today = now ?? DateTime.now();
    String money(double v) => '${CurrencyUtils.format(v, currency)} $currency';
    final price = (btcPrice != null && btcPrice > 0) ? btcPrice : null;

    final priceLine =
        price == null
            ? 'BTC price: unavailable — do not estimate fiat values of sats, '
                'or sats values of fiat.'
            : 'BTC price: ${money(price)} '
                '(1 $currency = ${SatConverter.formatSats((1e8 / price).round())} '
                'sats)';
    final stackValue =
        price == null ? '' : ' (≈ ${money(totalStackSats / 1e8 * price)})';
    final goalLine =
        stackGoalSats != null && stackGoalSats > 0
            ? 'Stack goal: ${SatConverter.formatSats(stackGoalSats)} sats '
                '(${(totalStackSats / stackGoalSats * 100).toStringAsFixed(1)}% '
                'reached)\n'
            : '';
    final isCurrent = month.year == today.year && month.month == today.month;
    final period =
        '${DateFormat.yMMMM().format(month)}'
        '${isCurrent ? ' (month to date)' : ' (complete month)'}';

    final head =
        '''You are a Bitcoin-native personal finance analyst embedded in Sats Stack, a privacy-first budgeting app. You give concise, actionable advice grounded in the user's real financial data. You think in sats. You are bullish on Bitcoin and understand sound money principles.

Current date: ${DateFormat('yyyy-MM-dd').format(today)}
The user's currency is $currency: give every fiat amount in it.
$priceLine

USER FINANCIAL SNAPSHOT
Total Bitcoin stack: ${SatConverter.formatSats(totalStackSats)} sats$stackValue
${goalLine}Figures for $period:
Income:   ${money(monthlyIncome)}
Spending: ${money(monthlySpending)}
Surplus:  ${money(monthlySurplus)}
Top spending categories:
''';

    const tail =
        '\n\nKeep responses focused and practical. When suggesting actions, '
        'quantify them in both fiat and sats. Do not repeat the user\'s data '
        'back verbatim — use it to inform your advice.';

    final ranked =
        spendingByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final lines = <String>[];
    var used = head.length + tail.length;
    for (final e in ranked) {
      final line = '  - ${e.key}: ${money(e.value)}';
      // +1 for the newline joining it to the previous line.
      final cost = line.length + (lines.isEmpty ? 0 : 1);
      if (used + cost > budget) break;
      lines.add(line);
      used += cost;
    }

    // Largest-first means an over-tight budget still yields the category that
    // matters most, and never an empty list where the user has spending — a
    // heading with nothing under it reads as "no data" to a small model.
    if (lines.isEmpty && ranked.isNotEmpty) {
      lines.add('  - ${ranked.first.key}: ${money(ranked.first.value)}');
    }

    return '$head${lines.join('\n')}$tail';
  }

  // ── Streaming chat ────────────────────────────────────────────────────────

  /// Streams response tokens from the currently active provider.
  ///
  /// If [client] is provided it is used for the request but NOT closed —
  /// the caller owns its lifecycle. Omit to get an auto-managed client.
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) => backend.chat(messages, client: client);

  // ── Vision chat ───────────────────────────────────────────────────────────

  /// Returns true if [modelName] suggests the model supports vision/image input.
  static bool looksLikeVisionModel(String? modelName) {
    if (modelName == null || modelName.isEmpty) return false;
    final lower = modelName.toLowerCase();
    return lower.contains('vision') ||
        lower.contains('llava') ||
        lower.contains('moondream') ||
        lower.contains('bakllava') ||
        lower.contains('vl');
  }

  /// Whether the active backend can read an image at all — see
  /// [chatWithImage]. None of the on-device backends can.
  bool get canReadImages => !_activeProvider.isOnDevice;

  /// Streams response tokens from the active provider for a vision (image+text)
  /// request. [base64Image] is raw base64-encoded image data (no data: prefix).
  Stream<String> chatWithImage(
    String prompt,
    String base64Image, {
    String mimeType = 'image/jpeg',
    http.Client? client,
  }) async* {
    switch (_activeProvider) {
      case AiProvider.ollama:
        yield* _ollamaChatWithImage(prompt, base64Image, client: client);
      case AiProvider.lmStudio:
        yield* _openAiChatWithImage(
          prompt,
          base64Image,
          mimeType: mimeType,
          baseUrl: _lmStudioBaseUrl,
          model: _lmStudioSelectedModel,
          apiKey: '',
          client: client,
        );
      case AiProvider.maple:
        yield* _openAiChatWithImage(
          prompt,
          base64Image,
          mimeType: mimeType,
          baseUrl: _mapleBaseUrl,
          model: _mapleSelectedModel,
          apiKey: _mapleApiKey,
          client: client,
        );
      case AiProvider.claude:
      case AiProvider.chatGpt:
      case AiProvider.gemini:
      case AiProvider.grok:
        // Every hosted provider reads images, and they are by some margin the
        // best thing to point the receipt import at.
        yield* cloudBackendFor(_activeProvider.cloudProvider!).chatWithImage(
          prompt,
          base64Image,
          mimeType: mimeType,
          client: client,
        );
      case AiProvider.appleIntelligence:
      case AiProvider.geminiNano:
        // Neither on-device backend takes an image on the path this app uses:
        // Apple's Foundation Models bridge here is text-only, and ML Kit's
        // Prompt API exposes multimodal input separately from the text stream.
        //
        // Thrown rather than silently returning nothing, because the caller is
        // the receipt-photo import — a blank answer there looks like the model
        // failed to read the image rather than like the wrong backend being
        // selected, and the user needs to know which.
        throw InferenceException(
          '${backend.displayName} cannot read images. Switch to Ollama or a '
          'hosted model in Settings to import from a photo.',
        );
    }
  }

  Stream<String> _ollamaChatWithImage(
    String prompt,
    String base64Image, {
    http.Client? client,
  }) async* {
    final model = _selectedModel;
    if (model == null || model.isEmpty) {
      throw StateError('No Ollama model selected');
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': prompt,
            'images': [base64Image],
          },
        ],
        'stream': true,
      });

      final streamedResponse = await c
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (streamedResponse.statusCode != 200) {
        throw Exception('Ollama returned ${streamedResponse.statusCode}');
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .idleTimeout(const Duration(seconds: 120), 'The model')
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          if (data['done'] == true) return;
          final token =
              (data['message'] as Map<String, dynamic>?)?['content']
                  as String? ??
              '';
          if (token.isNotEmpty) yield token;
        } catch (_) {}
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  Stream<String> _openAiChatWithImage(
    String prompt,
    String base64Image, {
    String mimeType = 'image/jpeg',
    required String baseUrl,
    required String? model,
    required String apiKey,
    http.Client? client,
  }) async* {
    if (model == null || model.isEmpty) {
      throw StateError('No model selected');
    }

    final ownedClient = client == null;
    final c = client ?? http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/chat/completions'),
      );
      request.headers['Content-Type'] = 'application/json';
      if (apiKey.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }
      request.body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
              },
              {'type': 'text', 'text': prompt},
            ],
          },
        ],
        'stream': true,
      });

      final streamedResponse = await c
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (streamedResponse.statusCode != 200) {
        throw Exception('Server returned ${streamedResponse.statusCode}');
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .idleTimeout(const Duration(seconds: 120), 'The model')
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        if (!line.startsWith('data:')) continue;
        // `substring(5).trim()` rather than matching the exact string
        // 'data: [DONE]': the space after the colon is optional in SSE, and a
        // server that omits it (or adds trailing whitespace) used to fall
        // through the terminator check and then through the 'data: ' prefix
        // filter, so the stream just ended with no explicit finish.
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') return;
        if (payload.isEmpty) continue;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          final choices = data['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final token = delta?['content'] as String? ?? '';
          if (token.isNotEmpty) yield token;
        } catch (_) {}
      }
    } finally {
      if (ownedClient) c.close();
    }
  }

  // ── Monthly insight ───────────────────────────────────────────────────────

  Future<String?> loadCachedInsight() async {
    final rows =
        await (_db.select(_db.appSettings)..where(
          (t) => t.key.equals(AppConstants.settingMonthlyInsight),
        )).get();
    return rows.isNotEmpty ? rows.first.value : null;
  }

  Future<bool> isInsightStale() async {
    final dateRows =
        await (_db.select(_db.appSettings)..where(
          (t) => t.key.equals(AppConstants.settingMonthlyInsightDate),
        )).get();
    if (dateRows.isEmpty) return true;
    final stored = DateTime.tryParse(dateRows.first.value);
    if (stored == null) return true;
    return DateTime.now().difference(stored).inDays >= 30;
  }

  Future<String> generateMonthlyInsight({
    required int totalStackSats,
    required double? btcPrice,
    required String currency,
    required DateTime month,
    required double monthlyIncome,
    required double monthlySpending,
    required double monthlySurplus,
    required Map<String, double> spendingByCategory,
    int? stackGoalSats,
  }) async {
    final systemPrompt = buildSystemPrompt(
      totalStackSats: totalStackSats,
      btcPrice: btcPrice,
      currency: currency,
      month: month,
      monthlyIncome: monthlyIncome,
      monthlySpending: monthlySpending,
      monthlySurplus: monthlySurplus,
      spendingByCategory: spendingByCategory,
      stackGoalSats: stackGoalSats,
    );

    const userPrompt =
        'Give me a 2-3 sentence insight about my finances. '
        'Be specific and honest. Call out the single most important pattern '
        'or opportunity you see. Quantify it in both fiat and sats.';

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];

    final buffer = StringBuffer();
    await for (final token in chat(messages)) {
      buffer.write(token);
    }
    final insight = buffer.toString().trim();
    // Not cached: an empty answer saved as the month's insight would stand
    // until the next month made it stale.
    if (insight.isEmpty) {
      throw InferenceException(
        '${backend.displayName} returned an empty answer.',
      );
    }

    await _upsertSetting(AppConstants.settingMonthlyInsight, insight);
    await _upsertSetting(
      AppConstants.settingMonthlyInsightDate,
      DateTime.now().toIso8601String(),
    );

    return insight;
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Deletes every stored chat transcript.
  ///
  /// Each question and answer used to be written to `ai_conversations` and
  /// never read back — no screen shows them — so they only accumulated in the
  /// database, and so in every export of it. Nothing writes there now; this
  /// clears what earlier builds left, and is cheap once the table is empty.
  Future<void> clearStoredTranscripts() => _db.delete(_db.aiConversations).go();
}
