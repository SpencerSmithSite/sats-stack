import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/device_memory.dart';
import 'package:sats_stack/core/services/inference/gemini_nano_backend.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';
import 'package:sats_stack/core/services/inference/platform_llm_backend.dart';
import 'package:sats_stack/core/services/inference/local_model_backend.dart';
import 'package:sats_stack/core/services/ollama_service.dart';

void main() {
  group('AiProvider persistence', () {
    test('every provider round-trips through its key', () {
      for (final p in AiProvider.values) {
        expect(AiProvider.fromKey(p.key), p, reason: 'round-trip for ${p.name}');
      }
    });

    test('an unknown key falls back to Ollama rather than throwing', () {
      // A backend removed in a later build must not break a settings read.
      expect(AiProvider.fromKey('a-backend-that-no-longer-exists'),
          AiProvider.ollama);
      expect(AiProvider.fromKey(null), AiProvider.ollama);
    });

    test('keys are unique — a collision would silently merge two backends', () {
      final keys = AiProvider.values.map((p) => p.key).toSet();
      expect(keys.length, AiProvider.values.length);
    });

    test('exactly the hosted backends are marked as leaving the device', () {
      // The one claim in the app that must never be wrong. Stated as "privacy
      // and having a named recipient are opposites" rather than by listing the
      // hosted providers, so adding a backend cannot pass this test by being
      // forgotten — a new value with no `dataRecipient` that claims privacy it
      // does not have will fail here.
      for (final p in AiProvider.values) {
        expect(p.isPrivate, p.dataRecipient == null,
            reason: '${p.name}: isPrivate must match having a data recipient');
      }
      expect(
        AiProvider.values.where((p) => !p.isPrivate).toSet(),
        {
          AiProvider.maple,
          AiProvider.claude,
          AiProvider.chatGpt,
          AiProvider.gemini,
          AiProvider.grok,
        },
      );
    });

    test('only a backend with a server the user runs offers a URL field', () {
      // Null hides the URL box. On-device backends have nothing to point at,
      // and a hosted service has one fixed endpoint the user must not be able
      // to mistype their finances into.
      for (final p in AiProvider.values) {
        expect(p.defaultUrl == null, p.isOnDevice || p.needsApiKey,
            reason: '${p.name}: defaultUrl disagrees with how it is configured');
      }
    });
  });

  group('Platform backend visibility', () {
    // Drives which chips the Settings picker shows. Getting this wrong in the
    // permissive direction leaves a permanently dead row on hardware that can
    // never use it; in the strict direction it hides the only place a pending
    // download can be started from.
    test('Apple: only fixable or ready states are offered', () {
      expect(PlatformLlmState.available.worthOffering, isTrue);
      expect(PlatformLlmState.notEnabled.worthOffering, isTrue,
          reason: 'the row is how the user learns where the switch is');
      expect(PlatformLlmState.modelNotReady.worthOffering, isTrue);

      expect(PlatformLlmState.notEligible.worthOffering, isFalse,
          reason: 'this hardware can never run it — a dead row helps nobody');
      expect(PlatformLlmState.osTooOld.worthOffering, isFalse);
      expect(PlatformLlmState.unsupportedPlatform.worthOffering, isFalse);
      expect(PlatformLlmState.unknown.worthOffering, isFalse);
    });

    test('Nano: downloadable is offered, unavailable is not', () {
      // The distinction that matters. Nano's weights are not present by
      // default, so `downloadable` is one tap away while `unavailable` is never
      // happening — collapsing them would tell someone with a supported phone
      // that their phone is unsupported.
      expect(GeminiNanoState.available.worthOffering, isTrue);
      expect(GeminiNanoState.downloadable.worthOffering, isTrue);
      expect(GeminiNanoState.downloading.worthOffering, isTrue);

      expect(GeminiNanoState.unavailable.worthOffering, isFalse);
      expect(GeminiNanoState.unsupportedPlatform.worthOffering, isFalse);
      expect(GeminiNanoState.unknown.worthOffering, isFalse);
    });

    test('Nano: every reason string the Kotlin bridge emits is mapped', () {
      // These five are the exact strings GeminiNanoBridge.availability returns.
      // An unmapped one lands on `unknown`, which hides the backend.
      for (final entry in {
        'available': GeminiNanoState.available,
        'downloadable': GeminiNanoState.downloadable,
        'downloading': GeminiNanoState.downloading,
        'unavailable': GeminiNanoState.unavailable,
        'unsupported_platform': GeminiNanoState.unsupportedPlatform,
      }.entries) {
        expect(GeminiNanoState.fromReason(entry.key), entry.value);
      }
      expect(GeminiNanoState.fromReason('something-new'),
          GeminiNanoState.unknown);
    });

    test('Apple: every reason string the Swift bridge emits is mapped', () {
      for (final entry in {
        'available': PlatformLlmState.available,
        'device_not_eligible': PlatformLlmState.notEligible,
        'not_enabled': PlatformLlmState.notEnabled,
        'model_not_ready': PlatformLlmState.modelNotReady,
        'os_too_old': PlatformLlmState.osTooOld,
      }.entries) {
        expect(PlatformLlmState.fromReason(entry.key, true), entry.value);
      }
      // Unrecognised + supported is a genuinely unknown state; unrecognised +
      // unsupported means there is no bridge here at all.
      expect(PlatformLlmState.fromReason('brand-new', true),
          PlatformLlmState.unknown);
      expect(PlatformLlmState.fromReason(null, false),
          PlatformLlmState.unsupportedPlatform);
    });
  });

  group('InferenceBackend.flattenMessages', () {
    test('a lone user turn is not labelled', () {
      // Labelling a single turn "User:" is noise a small model may echo back.
      final flat = InferenceBackend.flattenMessages([
        {'role': 'user', 'content': 'How much did I spend on dining?'},
      ]);
      expect(flat.system, isNull);
      expect(flat.prompt, 'How much did I spend on dining?');
    });

    test('system turns are separated from the prompt', () {
      final flat = InferenceBackend.flattenMessages([
        {'role': 'system', 'content': 'You are a finance analyst.'},
        {'role': 'user', 'content': 'Hello'},
      ]);
      expect(flat.system, 'You are a finance analyst.');
      expect(flat.prompt, 'Hello');
    });

    test('multi-turn conversations keep speaker labels', () {
      final flat = InferenceBackend.flattenMessages([
        {'role': 'system', 'content': 'Be brief.'},
        {'role': 'user', 'content': 'Hi'},
        {'role': 'assistant', 'content': 'Hello'},
        {'role': 'user', 'content': 'And dining?'},
      ]);
      expect(flat.system, 'Be brief.');
      expect(flat.prompt, 'User: Hi\n\nAssistant: Hello\n\nUser: And dining?');
    });

    test('multiple system turns are joined, not dropped', () {
      final flat = InferenceBackend.flattenMessages([
        {'role': 'system', 'content': 'One.'},
        {'role': 'system', 'content': 'Two.'},
        {'role': 'user', 'content': 'Hi'},
      ]);
      expect(flat.system, 'One.\n\nTwo.');
    });

    test('an empty system turn is treated as absent', () {
      final flat = InferenceBackend.flattenMessages([
        {'role': 'system', 'content': ''},
        {'role': 'user', 'content': 'Hi'},
      ]);
      expect(flat.system, isNull);
    });
  });

  group('System prompt sizing', () {
    // Enough categories that a small budget genuinely has to drop some. With
    // the nine seeded categories the app ships, the budget never binds — the
    // framing text dwarfs the data — so the sizing only matters once the
    // prompt grows. These tests exist to keep it correct when it does.
    final spending = {
      for (var i = 0; i < 100; i++) 'Category number $i': (100 - i) * 100.0,
    };

    String build(int budget) => OllamaService.composeSystemPrompt(
          totalStackSats: 5000000,
          btcPrice: 65000,
          monthlyIncome: 6000,
          monthlySpending: 4000,
          monthlySurplus: 2000,
          spendingByCategory: spending,
          stackGoalSats: 21000000,
          budgetChars: budget,
        );

    int categoryCount(String prompt) =>
        RegExp(r'^  - ', multiLine: true).allMatches(prompt).length;

    test('the prompt fits the budget it is given', () {
      // The whole point: Apple Intelligence and Gemini Nano get ~4000, and
      // overfilling a small window degrades the answer rather than erroring.
      for (final budget in [3000, 4000, 6000, 8000, 12000, 24000]) {
        expect(build(budget).length, lessThanOrEqualTo(budget),
            reason: 'overflowed a ${budget}-char budget');
      }
    });

    test('a smaller budget sends fewer categories, not a truncated one', () {
      final small = build(3000);
      final large = build(24000);

      expect(categoryCount(small), lessThan(categoryCount(large)));
      // Whole lines only — never a category cut mid-word.
      for (final line in small.split('\n').where((l) => l.startsWith('  - '))) {
        expect(line, matches(RegExp(r'^  - .+: \$\d+$')));
      }
    });

    test('categories are dropped largest-value-last', () {
      // An over-tight budget must still carry the spending that matters most.
      final small = build(3000);
      expect(small, contains('Category number 0:'),
          reason: 'the largest category must survive any budget');
      expect(small, isNot(contains('Category number 99:')),
          reason: 'the smallest is the first to go');
      // And the boundary is a real cut, not everything squeaking in.
      expect(categoryCount(small), lessThan(spending.length));
    });

    test('the headline figures survive even an absurd budget', () {
      // A prompt missing the actual numbers is useless at any size, so these
      // are never dropped — the budget only flexes the category list.
      final tiny = build(200);
      expect(tiny, contains('5000000 sats'));
      expect(tiny, contains('Monthly surplus'));
      expect(categoryCount(tiny), 1,
          reason: 'one category is kept rather than an empty heading');
    });

    test('no categories means no orphaned bullet', () {
      final none = OllamaService.composeSystemPrompt(
        totalStackSats: 0,
        btcPrice: 65000,
        monthlyIncome: 0,
        monthlySpending: 0,
        monthlySurplus: 0,
        spendingByCategory: const {},
        budgetChars: 4000,
      );
      expect(categoryCount(none), 0);
      expect(none, contains('Monthly surplus'));
    });

    test('a large budget includes everything available', () {
      expect(categoryCount(build(24000)), spending.length,
          reason: 'a hosted model should get the full picture');
    });
  });

  group('LocalModelChoice catalogue', () {
    tearDown(() => DeviceMemory.debugSetTotalMb(null));

    test('ids are unique and every id resolves', () {
      final ids = LocalModelChoice.catalogue.map((m) => m.id).toSet();
      expect(ids.length, LocalModelChoice.catalogue.length);
      for (final m in LocalModelChoice.catalogue) {
        expect(LocalModelChoice.byId(m.id).id, m.id);
      }
    });

    test('an id from another device resolves instead of throwing', () {
      // Someone picks the 8B on a desktop, then opens Settings on a phone.
      expect(() => LocalModelChoice.byId('qwen3-8b'), returnsNormally);
      expect(() => LocalModelChoice.byId('some-removed-model'), returnsNormally);
    });

    test('every model asks for more RAM than its weights occupy', () {
      // A model sized exactly to its own weights leaves nothing for the OS,
      // Flutter and the database, and gets the app killed under pressure.
      for (final m in LocalModelChoice.catalogue) {
        expect(m.minDeviceRamMb, greaterThan(m.ramMb),
            reason: '${m.name} must leave headroom beside its weights');
      }
    });

    test('phone limits are stricter than desktop ones', () {
      // Phones cap what a single app may hold well below physical memory, so a
      // model allowed on a 6 GB desktop may need a nominal 12 GB phone.
      for (final m in LocalModelChoice.catalogue) {
        if (m.minPhoneRamMb != null) {
          expect(m.minPhoneRamMb, greaterThanOrEqualTo(m.minDeviceRamMb),
              reason: '${m.name} phone floor must not undercut desktop');
        }
      }
    });

    test('catalogue is ordered smallest first', () {
      final sizes = LocalModelChoice.catalogue.map((m) => m.downloadMb).toList();
      final sorted = [...sizes]..sort();
      expect(sizes, sorted);
    });

    test('a device with too little memory is still offered the smallest', () {
      // Never returns empty: hiding the feature and explaining nothing is worse
      // than showing one option marked as too large.
      DeviceMemory.debugSetTotalMb(512);
      expect(LocalModelChoice.availableHere(), completion(hasLength(1)));
    });

    test('unknown memory is permissive rather than restrictive', () {
      DeviceMemory.debugSetTotalMb(null, unknown: true);
      expect(LocalModelChoice.availableHere(),
          completion(hasLength(LocalModelChoice.all.length)));
    });

    test('the recommendation is never the largest once three or more fit',
        () async {
      // The largest is the slowest; defaulting to it makes the feature feel
      // broken on exactly the machines that can run the most.
      DeviceMemory.debugSetTotalMb(64000);
      final tiers = await LocalModelChoice.tiersHere();
      if (tiers.length >= 3) {
        final recommended = await LocalModelChoice.recommendedHere();
        expect(recommended.id, isNot(tiers.last.model.id));
      }
    });

    test('the recommendation always matches the row labelled Recommended',
        () async {
      // These disagreed once; the default and the label must be one thing.
      for (final mb in [2600, 5000, 7000, 14000, 64000]) {
        DeviceMemory.debugSetTotalMb(mb);
        final tiers = await LocalModelChoice.tiersHere();
        final labelled = tiers
            .firstWhere((t) => t.tier == LocalModelTier.recommended)
            .model;
        expect((await LocalModelChoice.recommendedHere()).id, labelled.id,
            reason: 'disagreement at ${mb}MB');
      }
    });

    test('tiers never exceed three and are ordered smallest first', () async {
      for (final mb in [2600, 5000, 7000, 14000, 64000]) {
        DeviceMemory.debugSetTotalMb(mb);
        final tiers = await LocalModelChoice.tiersHere();
        expect(tiers.length, inInclusiveRange(1, 3), reason: 'at ${mb}MB');
        final sizes = tiers.map((t) => t.model.downloadMb).toList();
        expect(sizes, [...sizes]..sort(), reason: 'at ${mb}MB');
      }
    });

    test('all weights are ungated Apache-2.0 Qwen builds', () {
      // Gemma's litert-community repos are gated behind a HuggingFace account
      // and return HTTP 401 — fatal for a backend whose whole promise is "no
      // account, no key".
      for (final m in LocalModelChoice.catalogue) {
        expect(m.url, contains('litert-community/Qwen3'),
            reason: '${m.name} must come from an ungated repository');
        expect(m.url, endsWith('.litertlm'),
            reason: '${m.name} must be the format LiteRT-LM reads');
      }
    });
  });
}
