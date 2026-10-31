# Audit — full codebase scan, 2026-10-31

**Findings only, nothing fixed yet.** Each one is open until a PR fixes it; when one lands, mark its **Status** with the PR number. The earlier audits (2026-10-17, the 2026-10-18 and 2026-10-21 passes, and the record of PRs #22–#54) were in this file until now. They are in git: `git show ef5b956:docs/AUDIT.md`.

**77 findings: 1 High, 32 Medium, 44 Low.** Fix the High first: A-1, re-importing a statement through the AI tier double-counts spending.

## How this scan was done

- **Code review, five areas at once.** Each was read file by file by a separate read-only reviewer:
  - **D:** data layer and core services
  - **B:** Bitcoin and network
  - **A:** AI and statement import
  - **U:** UI screens and widgets
  - **P:** native configuration, CI and dependencies

  Every finding cites `file:line`. I re-checked the most serious ones against the code myself (A-1, A-2, A-5, B-1, B-2, D-3, D-4, D-6, P-1, P-2, U-1, U-3, U-5, U-6), merged six that two reviewers found separately, and dropped one claim that was wrong.
- **Runtime.** I built the macOS app and ran a copy under a throwaway bundle id, so your real data was not touched, and sampled its sockets ten times a second.
  - Result: a fresh install sitting at onboarding opens **no outbound connections at all**. The only socket is the debug-only Dart VM service on loopback.
  - Not done: walking through the screens. Access to the app was declined, so everything after onboarding comes from the code review.
- **Tools.**
  - `flutter analyze`: clean.
  - `flutter pub outdated`: see P-4.
  - `flutter test --coverage`: 559 tests pass, 57 % line coverage. See T-1.
- **Not covered:** a real electrs or Fulcrum server (macOS blocks Dart from the local network here), and a real phone or simulator.

Severity: **High** loses or misstates money or data, or sends data somewhere the user wasn't told. **Medium** is a real bug, leak or slowdown a user will meet. **Low** is an edge case, hardening or upkeep.

## Index

| ID | Sev | Category | Finding |
|---|---|---|---|
| A-1 | High | correctness | AI-tier imports are not deduplicated — re-importing double-counts spending |
| A-2 | Medium | reliability, privacy | Hosted AI output capped at 4,096 tokens — long statements upload, then parse to nothing |
| A-3 | Medium | reliability | AI import input ignores the backend's context window |
| A-4 | Medium | correctness | Saved column mappings book card charges as income |
| A-5 | Medium | privacy | Refreshing an insight sends figures to a hosted provider without naming it |
| A-6 | Medium | privacy | The chat screen never names who receives the figures |
| A-7 | Medium | privacy | Picked statements and photos are left in app caches |
| A-8 | Medium | performance | PDF and CSV parsing run unbounded on the UI isolate |
| A-10 | Medium | performance | Per-token full rebuilds and quadratic string growth while streaming |
| B-1 | Medium | correctness | Pagination cap truncates an address's history, and the sync then deletes the rest |
| B-2 | Medium | security, privacy | Electrum defaults to plain TCP — readable and forgeable |
| B-3 | Medium | reliability | A dropped Electrum connection takes minutes to fail |
| B-4 | Medium | reliability | Esplora rate-limit handling defeats itself on large wallets |
| B-5 | Medium | performance, privacy | Sync prices one day a second, sending each transaction's exact timestamp |
| B-6 | Medium | privacy | The Add Wallet privacy notice is wrong in both directions |
| B-7 | Medium | correctness | An ambiguous `xpub` with no history yet is stored as legacy for good |
| D-1 | Medium | performance | Change triggers read the whole transactions table on every change |
| D-2 | Medium | performance | Dashboard, per-wallet and analytics recompute from every row ever recorded |
| D-3 | Medium | correctness | Recurring transactions are only generated on a cold start |
| D-4 | Medium | privacy | "Reset all data" leaves a full copy of the old database on disk |
| D-5 | Medium | reliability | Restore checks only the file header, and a database that won't open bricks launch |
| P-1 | Medium | security | No app-switcher or screenshot protection on any platform |
| P-2 | Medium | privacy | iOS database goes into iCloud and device backups; Android deliberately excludes it |
| P-3 | Medium | supply-chain | GitHub Actions pinned to mutable tags, including those holding secrets |
| P-4 | Medium | supply-chain | End-of-life SQLite libs, a discontinued keychain backend, wide version lag |
| P-5 | Medium | privacy | ML Kit GenAI may bring Google's telemetry transport into Android builds |
| U-1 | Medium | correctness | Re-running onboarding resets the AI provider and its URL |
| U-2 | Medium | privacy | The Bitcoin routing banner describes unsaved text, not the saved server |
| U-3 | Medium | privacy | Onboarding accepts an unusable Esplora URL without saying so |
| U-4 | Medium | privacy | Stored API keys are preloaded into Settings and shown with one tap |
| U-5 | Medium | performance | The import screen creates its Drift stream in `build()` |
| U-6 | Medium | reliability | Several saves and deletes fail without telling the user |
| U-7 | Medium | accessibility | Rows overflow at large text sizes |
| A-9 | Low | correctness | Chat system prompt goes stale for the whole session |
| A-11 | Low | performance | Per-row regex compile against the whole file when checking currency |
| A-12 | Low | reliability | Vision paths duplicate the backends and lose errors |
| A-13 | Low | reliability | CloudBackend's error-body read has no timeout |
| A-14 | Low | correctness | AI rows are validated loosely |
| A-15 | Low | correctness | Monthly insight staleness ignores the month boundary |
| A-16 | Low | maintainability | `AiProvider.isPrivate` is a trap |
| A-17 | Low | security | Credentials outside the keychain: legacy Maple key, `user:pass@` URLs |
| A-18 | Low | correctness | Smaller import and copy issues (vision warning, consent text, date sniffing, CSV quoting) |
| B-8 | Low | reliability, security | No bounds on what a hostile server can send |
| B-9 | Low | maintainability, privacy | Three different tests for "is the default server in use" |
| B-10 | Low | maintainability | Unused, incorrect Electrum helpers |
| B-11 | Low | correctness | Extended-key depth is never checked |
| D-6 | Low | correctness | Spending exactly equal to a budget is flagged as over |
| D-7 | Low | correctness | Uncategorised spending counts as "Other" everywhere but Budgets |
| D-8 | Low | correctness | Deleting a category leaves learned import mappings pointing at it |
| D-9 | Low | reliability | Alerts are marked sent before they are delivered |
| D-10 | Low | performance | Much work is awaited before the first frame |
| D-11 | Low | correctness | Calendar dates stored as instants and read back in local time |
| D-12 | Low | correctness | Double-tapping Add Wallet can track the same xpub twice |
| D-13 | Low | performance, maintainability | `usageCounts` loads rows to count them; a misplaced doc comment |
| U-8 | Low | correctness | Switching currency briefly mislabels the price, or keeps it mislabelled if the write fails |
| U-9 | Low | correctness | Budget edit field shows the wrong currency symbol when there is no rate |
| U-10 | Low | correctness, performance | The stack chart misrepresents time and redraws on every price tick |
| U-11 | Low | correctness | The date picker asserts on imported dates outside its range |
| U-12 | Low | accessibility | Sheets that don't scroll |
| U-13 | Low | accessibility | Low-contrast text the `legibleAccent` pass missed |
| U-14 | Low | accessibility | Tap targets under 48 px |
| U-15 | Low | performance, privacy | Opening Settings calls the AI provider even if Servers is never opened |
| U-16 | Low | privacy | Copied chat answers stay on the clipboard |
| U-17 | Low | performance | Search reruns the whole filter and grouping on every keystroke |
| U-18 | Low | correctness | The price chip's age label can stay at "just now" |
| U-19 | Low | reliability | Electrum "Save and test" replaces a working server before testing the new one |
| U-20 | Low | reliability | Onboarding's finish has no double-tap guard or error handling |
| U-21 | Low | reliability | `setState` can run after dispose in the insight flow |
| U-22 | Low | maintainability, reliability | Duplicated colour parsers that throw on bad data |
| P-6 | Low | reliability | The test network guard misses raw sockets |
| P-7 | Low | privacy | No privacy manifest for the app itself |
| P-8 | Low | privacy | Amounts in notifications, including on the lock screen |
| P-9 | Low | reliability | CI never builds Apple release configs; no job timeouts; Linux/Windows unbuilt |
| P-10 | Low | security | macOS: no hardened runtime, and no local-network purpose string |
| P-11 | Low | maintainability | Stale configuration comments; strict analyzer modes off |
| P-12 | Low | security | Committed test TLS key (acceptable, but flagged by scanners) |
| T-1 | Low | maintainability | Large screens have no tests at all |

---

## A — AI and statement import

### A-1 · High · correctness — AI-tier imports are not deduplicated
- **Where:** `lib/core/services/import_service.dart:2955` (`rawDescription: description`), the description at `:1174`, and the hashes at `:1789-1796` and `:1876-1882`.
- **What:** On the AI tiers, `description` is the model's own rewording of the row. Both dedup hashes (`computeHash` and `HashUtils.transactionDedupHash`) are built from `tx.rawDescription`, which is set to that same text.
- **Impact:** Model wording varies between runs and differs from the rules tier's raw bank text. So importing overlapping statements, or the same file once through AI and once through the rules tier, inserts the same transaction twice. Nothing in the preview flags it, and spending and budgets are silently inflated.
- **Fix direction:** Build the dedup key from file-derived data only (date, amount, and the source row text or a normalised form of it). Flag near-duplicates (same source, date and amount) in the preview.
- **Status:** fixed in #56. Before the preview, rows that match ones the source already holds (same day, amount and direction, counted, with an exact description matched first) are unticked and labelled "Already imported?", with a note saying how many. The user can tick any back in, so two different same-day transactions are never dropped silently. Pinned by `ai_import_dedup_test`.

### A-2 · Medium · reliability, privacy — Hosted AI output is capped at 4,096 tokens
- **Where:** `lib/core/services/inference/cloud_backend.dart:468` (sent at `:351`, `:407`); `import_service.dart:1105` (`maxLen = 100000`), `:2459-2483`.
- **What:** Up to 100,000 characters go in, but the answer is cut off at about 90 JSON rows. The truncated array has no closing `]`, so `_extractJsonArray` fails and the AI parse returns null.
- **Impact:** A statement with more than about 90 rows is uploaded in full to the provider, then yields nothing. The app falls back to the rules tier or the heuristic, or shows "could not extract", and never says why. The user paid for the call and their data left the device for no result.
- **Fix direction:** Size the input to what the output can carry, or chunk it. Raise the import's output cap, or recover the complete objects from a truncated array and say so.
- **Status:** open

### A-3 · Medium · reliability — AI import input ignores the backend's context window
- **Where:** `import_service.dart:1105-1108`; `lib/core/services/inference/remote_backends.dart:121-125`.
- **What:** The fixed 100,000-character cap applies to every backend, though `contextBudgetChars` is 4,000 for Apple Intelligence and Gemini Nano. Ollama requests send no `options.num_ctx`.
- **Impact:**
  - On-device: overflow errors are swallowed and the user waits for nothing.
  - Ollama: the server truncates the prompt itself, so rows are lost with no notice. Whether it drops the leading instructions is unverified.
- **Fix direction:** Size the input from `contextBudgetChars`, pass `num_ctx` to Ollama, and set the truncation notice from the real limit. Skip the AI tier when the file cannot fit.
- **Status:** open

### A-4 · Medium · correctness — Saved column mappings book card charges as income
- **Where:** `import_service.dart:1624-1625`, called from `:924`.
- **What:** `direction = mappingAmountIsSigned ? (raw < 0 ? 'debit' : 'credit') : 'debit'`. `parseWithMapping` never gets the source type, so it lacks the rules tier's `chargesMaySignPositive` / `positiveIsDebit` handling. An unsigned column becomes all-debit.
- **Impact:** For a card that exports purchases as positive amounts, a saved mapping, which is the first tier tried on every later import, files every purchase as income.
- **Fix direction:** Pass the source type into `parseWithMapping` and share the direction rules with `_parseRowsGeneric`.
- **Status:** open

### A-5 · Medium · privacy — Refreshing an insight sends figures to a hosted provider without naming it
- **Where:** `lib/features/dashboard/widgets/ai_insight_card.dart:58-59`, `:101`, `:139`.
- **What:** The "Sends last month's totals… to *recipient*" line shows only when `_needsConsentToGenerate`, which requires `!_hasInsight`. With an insight already cached, for example one made earlier with a local Ollama, only a refresh icon shows, and tapping it uploads the month to whichever provider is now selected.
- **Impact:** After switching to Claude or ChatGPT, a user can send a financial snapshot to a third party from a control that doesn't say where it goes.
- **Fix direction:** Show the recipient line, or confirm, whenever `offDeviceRecipient != null`.
- **Status:** open

### A-6 · Medium · privacy — The chat screen never names who receives the figures
- **Where:** `lib/features/ai_chat/ai_chat_screen.dart:455-461`; the claim that it does is at `cloud_backend.dart:158-161`.
- **What:** The empty state says only "Your financial data is injected as context." `AiPrivacyDisclosure` appears only in the chat's settings sheet, and only for providers with a server URL. The screen never reads `sendsDataOffDevice`.
- **Impact:** The most-used sending path, every question carrying the full snapshot, gives no reminder that Anthropic, OpenAI, Google or xAI receives it. The documented guarantee is false.
- **Fix direction:** Show a compact recipient line in the chat whenever `sendsDataOffDevice`, or correct the comment.
- **Status:** open

### A-7 · Medium · privacy — Picked statements and photos are left in app caches
- **Where:** `lib/screens/import/import_file_screen.dart:325-329`, `:661-666`. Nothing in `lib` calls `clearTemporaryFiles()` (checked).
- **What:** On mobile, `file_picker` and `image_picker` copy the chosen file into the app's cache. Nothing deletes the copy.
- **Impact:** Whole bank statements and statement photos stay on disk after the import, outside the database that "Reset all data" clears. The per-platform behaviour is from the plugins' documentation, not verified here.
- **Fix direction:** Delete the picked copy when an import finishes or is cancelled, and in reset.
- **Status:** open

### A-8 · Medium · performance — PDF and CSV parsing run unbounded on the UI isolate
- **Where:** `import_service.dart:1661-1667`, `:2386-2393`, `:2402-2406`.
- **What:** `readAsBytes()` has no size check. `PdfTextExtractor.extractText()` and `CsvToListConverter().convert()` run synchronously on the main isolate, and the CSV is parsed up to three times on the fall-through path.
- **Impact:** A large statement freezes the UI for seconds, during which Cancel can't respond. A very large one can exhaust a phone's memory.
- **Fix direction:** Limit size at pick time, parse in `Isolate.run`, and parse once per import.
- **Status:** open

### A-9 · Low · correctness — Chat system prompt goes stale for the whole session
- **Where:** `ai_chat_screen.dart:86-90`, `:138-150`.
- **What:** The prompt is built once, and rebuilt only when the provider configuration changes. The tab stays alive.
- **Impact:** After an import, an edit or a new month, the AI answers from old figures. Both the AI and the UI reviewer found this; the comment at `:141` claiming the tab is disposed when you switch away is no longer true.
- **Fix direction:** Rebuild per send, or when transactions change.
- **Status:** open

### A-10 · Medium · performance — Per-token full rebuilds and quadratic string growth while streaming
- **Where:** `ai_chat_screen.dart:217-221`; `import_file_screen.dart:402-415`.
- **What:** Both the AI and the UI reviewer found this.
  - Chat: a `setState` per token rebuilds a non-lazy list of every bubble, each re-parsing Markdown, and starts a scroll animation.
  - Import: `_aiOutput += token` plus a whole-screen `setState`, per token.
- **Impact:** Jank on long answers and large imports.
- **Fix direction:** Throttle to once a frame, rebuild only the streaming bubble, and use a `StringBuffer`.
- **Status:** open

### A-11 · Low · performance — Per-row regex compile against the whole file when checking currency
- **Where:** `import_service.dart:503`, called per row at `:1175-1179`.
- **What:** A new `RegExp` is compiled for each row and run over the whole untruncated file, whenever the model's currency differs from the account's.
- **Impact:** Cost grows with rows times file size.
- **Fix direction:** Cache the answer per claimed code for the import.
- **Status:** open

### A-12 · Low · reliability — Vision paths duplicate the backends and lose errors
- **Where:** `lib/core/services/ollama_service.dart:1040-1170`.
- **What:** `_ollamaChatWithImage` and `_openAiChatWithImage` re-implement streaming. They throw a plain `Exception` and swallow every frame with `catch (_) {}`, `error` frames included.
- **Impact:** A rejected key or an out-of-memory error mid-stream ends as a generic failure, or as a partial result that looks complete.
- **Fix direction:** Move image chat into the backends, reusing their error and idle-timeout handling.
- **Status:** open

### A-13 · Low · reliability — CloudBackend's error-body read has no timeout
- **Where:** `cloud_backend.dart:703`.
- **What:** `response.stream.bytesToString()` on a non-200 response is unbounded, while `remote_backends.dart:364-367` caps the same job at 5 s.
- **Impact:** A stalled proxy leaves the spinner spinning, and the dashboard insight has no cancel.
- **Fix direction:** Use the same short timeout, and cap the body size.
- **Status:** open

### A-14 · Low · correctness — AI rows are validated loosely
- **Where:** `import_service.dart:816-823`, `:1166-1174`.
- **What:**
  - An amount given as a string (`"12.50"`) makes the row drop silently.
  - `DateTime.tryParse` accepts out-of-range dates, and `…Z` UTC timestamps can move a row across a day or month boundary.
  - A missing `direction` defaults to debit.
- **Impact:** Rows go missing or land in the wrong month, with no notice.
- **Fix direction:** Parse with `_parseAmount` and `_calendarDate`, and count dropped rows.
- **Status:** open

### A-15 · Low · correctness — Monthly insight staleness ignores the month boundary
- **Where:** `ollama_service.dart:1182-1191`.
- **What:** An insight is stale only 30 days after it was made, but it is about "last month".
- **Impact:** A September insight made on 2 October still shows on 1 November.
- **Fix direction:** Store the month it covers, and compare that.
- **Status:** open

### A-16 · Low · maintainability — `AiProvider.isPrivate` is a trap
- **Where:** `lib/core/models/ai_provider.dart:140`.
- **What:** It is true for Ollama and LM Studio whatever their URL. No runtime code reads it any more, only tests and comments. The test `isPrivate == (dataRecipient == null)` holds because both are wrong in the same way for a remote URL.
- **Impact:** A future caller would bring back the false "nothing leaves" claim.
- **Fix direction:** Rename it (for example `isPrivateByConstruction`), or remove it in favour of `OllamaService.recipientFor`.
- **Status:** open

### A-17 · Low · security — Credentials outside the keychain
- **Where:** `ollama_service.dart:503-514`; `remote_backends.dart:72`, `:77`.
- **What:**
  - If the keychain refuses, a legacy Maple key stays in plaintext in `AppSettings`.
  - Server URLs are stored and shown verbatim, so a `user:pass@` URL sits in the exported database and on screen.
- **Impact:** Credentials can leak through an export or a screenshot.
- **Fix direction:** Strip `userInfo` before storing or showing a URL, and warn when a plaintext key remains.
- **Status:** open

### A-18 · Low · correctness — Smaller import and copy issues
- **Where:** `import_file_screen.dart:602`, `:104`; `import_column_mapper_screen.dart:86`; `dashboard_service.dart:278`.
- **What:**
  - `looksLikeVisionModel` warns "may not support image analysis" for every hosted model, and all of them read images.
  - The consent text reads "…the server you configured (host)'s servers".
  - The column mapper picks DD/MM or MM/DD from only the first 3 rows, so a UK file whose first days are all 12 or under is read month-first and later rows are rejected.
  - The summary CSV writes category names unquoted, so a comma shifts columns and a leading `=` becomes a formula.
- **Fix direction:** Skip the vision warning for hosted providers, fix the copy, sample the whole column, and quote CSV fields with a formula-prefix guard.
- **Status:** open

---

## B — Bitcoin and network

### B-1 · Medium · correctness — Pagination cap truncates history, and the sync then deletes the rest
- **Where:** `lib/core/services/xpub_service.dart:195` (`_maxPagesPerAddress = 40`), `:714-740`, and the delete at `:1032-1035`.
- **What:**
  - At the cap, the loop returns a partial list with no error.
  - A server that pages in fewer than 25 rows ends paging after one page.
  - Pass 4 then deletes every stored row the scan didn't return.
- **Impact:** For an address with more than about 1,000 transactions, or a self-hosted Esplora still indexing, older rows are deleted along with their categories and notes. The only warning is a count.
- **Fix direction:** Throw when the cap is hit. Refuse, or ask before, a sync that would remove a large share of a wallet's rows.
- **Status:** fixed in #57. A capped address is reported, and rows the scan did not return are kept, not deleted, when an address was capped or when the server returned fewer transactions than the wallet holds with most of it missing (an indexing server). The sync result says how many were kept and why. Short pages from a non-standard server still end paging; that case is now covered by the second rule. Pinned by `xpub_truncated_scan_test`.

### B-2 · Medium · security, privacy — Electrum defaults to plain TCP
- **Where:** `lib/core/services/electrum_service.dart:23` (`_ssl = false`), `:147-153`; `AppConstants.defaultElectrumPort = 50001`; `wallet_history_section.dart:223-231`.
- **What:** Plain TCP is the default. The copy warns only that addresses "cross the network readable".
- **Impact:** On a shared network, someone in the path sees every scripthash. They can also return forged or empty history, which B-1's delete path then turns into lost rows.
- **Fix direction:** Default to TLS on 50002, or confirm before using plain TCP to a non-private host. Say in the copy that history can be forged as well as read.
- **Status:** open

### B-3 · Medium · reliability — A dropped Electrum connection takes minutes to fail
- **Where:** `electrum_service.dart:427-455`, `:301-313`.
- **What:** `_handleDone` fails only the calls already pending. Later `call()`s keep writing to the dead socket and each waits out the 30 s timeout. `fetchWindow`'s `Future.wait` isn't `eagerError`, and the limiter allows 16 calls in flight.
- **Impact:** A dropped connection mid-scan can hang behind a spinner for several minutes.
- **Fix direction:** Add a closed flag that makes `call()` throw at once, and use `eagerError: true`.
- **Status:** open

### B-4 · Medium · reliability — Esplora rate-limit handling defeats itself on large wallets
- **Where:** `xpub_service.dart:626-631`, `:648-656`, `:665`, `:688-701`.
- **What:**
  - Three workers send at about three times the old serial rate.
  - While one backs off after a 429, the other two keep sending.
  - A `Retry-After` over 30 s, or one given as a date, is ignored, and the request is retried after 0.5–1 s.
  - The third 429 aborts the whole scan, and nothing from it is kept.
- **Impact:** On public mempool.space, a large wallet may never finish syncing.
- **Fix direction:** Make backoff global across workers. Fail clearly on a long `Retry-After`. Adapt the spacing.
- **Status:** open

### B-5 · Medium · performance, privacy — Sync prices one day a second, sending each transaction's exact timestamp
- **Where:** `xpub_service.dart:1001-1010`; `lib/core/services/btc_price_service.dart:356-366`, `:554-556`, `:578-588`.
- **What:**
  - Pass 3 calls `getHistoricalPrice` once per day, throttled to 1 request a second, with `?timestamp=<block time>`, falling back to CoinGecko.
  - `prefetchHistoricalPrices`, a bulk fetch that sends no dates, is used by imports (`import_service.dart:1744`) but not here.
- **Impact:** First sync of a wallet with 300 transaction days spends five or more minutes on prices. Users who chose Electrum for privacy still send mempool.space a block-precise timestamp for every transaction, which points at the blocks holding them, alongside their IP. The banner says only "dates".
- **Fix direction:** Call `prefetchHistoricalPrices` before the per-day loop, as imports do, and make the banner exact.
- **Status:** open

### B-6 · Medium · privacy — The Add Wallet privacy notice is wrong in both directions
- **Where:** `lib/features/transactions/widgets/add_wallet_sheet.dart:341-342`, `:369`, `:400`.
- **What:** The notice keys only on `esploraBaseUrl != mempoolBaseUrl`, never on the data source.
  - With Electrum chosen, it says history comes from mempool.space.
  - With any other public instance set, it says "exclusively your custom server… nothing sent to public servers".
  - "Your xpub is never sent" is true, but every derived address is, and that links the wallet just the same.
- **Impact:** Users make privacy decisions on copy that is wrong.
- **Fix direction:** Build it from the same inputs as `DataRoutingBanner`, and say that addresses are sent.
- **Status:** open

### B-7 · Medium · correctness — An ambiguous `xpub` with no history yet is stored as legacy for good
- **Where:** `add_wallet_sheet.dart:67-70`; `xpub_service.dart:349-365`, `:836-841`.
- **What:**
  - Script-type detection runs only when the wallet is added. If it finds no history, the plain `xpub` is kept, and every later sync derives legacy addresses.
  - Detection also stops at the first type with history, so funds held under another type of the same key are never scanned.
- **Impact:** A new Ledger or Trezor native-SegWit account added before its first receive stays empty forever. The user has to delete it and add it again.
- **Fix direction:** Re-detect on rescan while the wallet is unresolved and empty, or ask the user for the type. Reuse the probe results in the first sync.
- **Status:** open

### B-8 · Low · reliability, security — No bounds on what a hostile server can send
- **Where:** `electrum_service.dart:387-391`; `xpub_service.dart:607`, `:617`; `lib/shared/utils/bitcoin_script.dart:120-135`, `:156`, `:163`.
- **What:**
  - Lines and HTTP bodies have no size cap.
  - An 8-byte varint can go negative and slip past the bounds check (throwing `RangeError`, not `FormatException`).
  - An output value with the top bit set parses as negative.
- **Impact:** Memory exhaustion is possible over plain TCP. Errors are inconsistent, but all are caught upstream.
- **Fix direction:** Cap sizes, and reject negative or over-long lengths and values.
- **Status:** open

### B-9 · Low · maintainability, privacy — Three different tests for "is the default server in use"
- **Where:**
  - `btc_price_service.dart:253-256` and `:500-503`: `contains('mempool.space')`
  - `:452-456`: any custom value
  - `add_wallet_sheet.dart:342`: exact equality
  - `bitcoin_servers_section.dart:141-144`: `contains` on unsaved text
- **What:** Each place decides differently. `BtcPriceService.loadSettings` also reads the URL without normalising it.
- **Impact:** The same URL counts as default on one screen and custom on another. That decides whether CoinGecko is contacted, and which privacy copy shows.
- **Fix direction:** One normalised `isDefaultEsplora` predicate, used everywhere.
- **Status:** open

### B-10 · Low · maintainability — Unused, incorrect Electrum helpers
- **Where:** `electrum_service.dart:190-225`.
- **What:** Nothing calls `getHistory` or `getTransaction`. `getTransaction` asks for verbose output, which electrs doesn't support, and swallows every error.
- **Fix direction:** Delete both. `ElectrumHistory` covers this.
- **Status:** open

### B-11 · Low · correctness — Extended-key depth is never checked
- **Where:** `xpub_service.dart:371-401`.
- **What:** A master (depth 0) or chain-level (depth 4) key is derived as `/chain/i` without complaint.
- **Impact:** A key exported at the wrong level shows as an empty wallet.
- **Fix direction:** Warn when the depth isn't 3.
- **Status:** open

---

## D — Data layer and core services

### D-1 · Medium · performance — Change triggers read the whole transactions table on every change
- **Where:** `lib/core/services/budget_service.dart:123-124`; `lib/main.dart:173-180`; `lib/core/services/transaction_service.dart:14-17`.
- **What:** `watchProgress` watches full `select(budgets)` and `select(transactions)` queries only to learn that something changed, and throws the rows away. `main.dart` keeps `watchAll()`, an ordered full select, alive for the whole process, just to call `checkAndNotify`.
- **Impact:** Every insert, edit or delete re-reads and maps the whole table at least twice on the UI isolate. That causes jank on large histories.
- **Fix direction:** Use `tableUpdates(...)` as the trigger, and keep `watchAll` for screens that render rows.
- **Status:** open

### D-2 · Medium · performance — Dashboard, per-wallet and analytics recompute from every row ever recorded
- **Where:** `lib/core/services/dashboard_service.dart:82-94`, `:151-156`, `:230`, `:305`, `:361-363`; `btc_price_service.dart:216`.
- **What:**
  - Each emission loads every transaction and filters, restates and sorts in Dart.
  - `watchDashboard` also watches `appSettings`, which the price service writes every 10 minutes and on resume, as do the notification ledger and recurring cursors.
  - `asyncMap` doesn't merge bursts of changes.
- **Impact:** O(n log n) over the whole history on every price tick and every change, twice (dashboard and per-wallet). The v7 date index goes unused.
- **Fix direction:** Do the month sums, stack total and recent-five in SQL, grouped by currency, over the indexed date range.
- **Status:** open

### D-3 · Medium · correctness — Recurring transactions are only generated on a cold start
- **Where:** `lib/main.dart:163`. It is the only caller, checked.
- **What:** The resume listener refreshes only the price.
- **Impact:** A phone app resumed for days without a cold start, or a desktop window left open, misses rent and salary entries. Budgets and the dashboard under-count, and alerts come late.
- **Fix direction:** Also run on resume and on a day-change timer. The cursor and hash already make repeat calls safe.
- **Status:** open

### D-4 · Medium · privacy — "Reset all data" leaves a full copy of the old database on disk
- **Where:** `lib/core/database/database.dart:544-547` (the `.bak`), `:381-397`; `danger_zone_section.dart:43`.
- **What:** Restoring a backup writes `<db>.sqlite.bak`, and nothing ever deletes it. Reset only runs `DELETE`s, with no `VACUUM` or `secure_delete`, so deleted rows also stay in free pages.
- **Impact:** After any import followed by "Delete Everything", the earlier database stays beside the live one, including transactions, xpubs and server URLs. The dialog promises permanent deletion.
- **Fix direction:** Remove the `.bak` once a restore succeeds and on reset, and `VACUUM` after reset.
- **Status:** open

### D-5 · Medium · reliability — Restore checks only the file header, and a database that won't open bricks launch
- **Where:** `lib/features/settings/widgets/data_section.dart` (`_looksLikeSqlite`); `lib/main.dart:72-102`.
- **What:** The only check is the `'SQLite format 3'` header. The first queries in `main()` are not guarded.
- **Impact:** A truncated, corrupt or foreign SQLite file passes the check, then throws before `runApp`, and the app can't launch. The good data sits in `.bak` with no way back to it.
- **Fix direction:** Open the candidate read-only first and check `integrity_check`, `user_version` and the expected tables. Catch open failures at startup and offer to restore the `.bak`.
- **Status:** open

### D-6 · Low · correctness — Spending exactly equal to a budget is flagged as over
- **Where:** `lib/core/models/budget_progress.dart:39` (`spentFiat > limit`); `budget_service.dart:166-168`.
- **What:** Spending is a running sum of doubles. In 20,000 random sets of cent amounts that add up exactly to the limit, 15 % compared as greater: for example `143.92000000000002 > 143.92`.
- **Impact:** The card turns red, an "exceeded by $0" alert fires, and that month's alert is used up.
- **Fix direction:** Compare in integer cents.
- **Status:** open

### D-7 · Low · correctness — Uncategorised spending counts as "Other" everywhere but Budgets
- **Where:** `budget_service.dart:164`, compared with `dashboard_service.dart:169`, `:187`, `:250`, `:342`.
- **What:** Budgets skip a `null` category. The dashboard, analytics and export treat it as `'Other'`.
- **Impact:** An "Other" budget disagrees with the pie chart and the export.
- **Fix direction:** One rule, used in all four places.
- **Status:** open

### D-8 · Low · correctness — Deleting a category leaves learned import mappings pointing at it
- **Where:** `lib/core/services/category_service.dart:136-157`; `import_service.dart:1984-1992`.
- **What:** Mappings and imported rows keep the deleted name, and mappings are applied without checking the category still exists. The check and the delete are also not one transaction.
- **Impact:** The next import files rows under a category that no longer exists, and they never count against a budget.
- **Fix direction:** Redirect or remove the mappings in the same transaction as the delete, or check the category when applying a mapping.
- **Status:** open

### D-9 · Low · reliability — Alerts are marked sent before they are delivered
- **Where:** `lib/core/services/notification_service.dart:94`, `:120`, `:145`, compared with `:224-226`, `:253`.
- **What:** `_claim` records the alert. `_show` then returns silently when not initialised, when permission is denied, or when the plugin throws.
- **Impact:** A user who allows notifications later gets nothing for the rest of the month, and the stack-goal alert for that amount never fires again.
- **Fix direction:** Claim only after a successful show.
- **Status:** open

### D-10 · Low · performance — Much work is awaited before the first frame
- **Where:** `lib/main.dart:87`, `:95`, `:99-133`, `:145`, `:148`; `ollama_service.dart:421`, `:448`, `:457`, `:460-461`.
- **What:** About 15 sequential round trips run before `runApp`: a full settings read, five keychain reads, possible keychain migrations, five more single-key reads of values already loaded, and three service initialisations.
- **Impact:** Slower cold start, most likely with macOS's file-based keychain. Timings were not measured.
- **Fix direction:** Read settings once and share them. Load API keys lazily, or after the first frame.
- **Status:** open

### D-11 · Low · correctness — Calendar dates stored as instants and read back in local time
- **Where:** drift's default timestamp storage (there is no `build.yaml`); `lib/shared/utils/date_range.dart:27-30`; `transaction_service.dart:265-322`.
- **What:** Picker and CSV dates are local midnight, stored as an instant. Months and recurring dates read them back with the device's current local fields.
- **Impact:** After moving to a timezone further west, a transaction on the 1st reads as the last day of the previous month, landing in the wrong budget and month, and recurring series shift with it. This was reasoned from the code, not run.
- **Fix direction:** Store date-only values as calendar dates.
- **Status:** open

### D-12 · Low · correctness — Double-tapping Add Wallet can track the same xpub twice
- **Where:** `lib/core/services/wallet_service.dart:53-65`; `wallets_table.dart`.
- **What:** `findByXpub` then `insert`, with no transaction and no unique index. Whether the UI already blocks a double tap is unverified.
- **Impact:** The same wallet counted twice doubles the stack.
- **Fix direction:** Do both in one transaction, or add a unique index on `xpub` that allows NULLs.
- **Status:** open

### D-13 · Low · performance, maintainability — `usageCounts` loads rows to count them; a misplaced doc comment
- **Where:** `category_service.dart:140-145`; `lib/shared/constants/app_constants.dart:67-77`, `:105`.
- **What:** `usageCounts` loads every row in a category only to take `.length`. Separately, `recurringCursorKey`'s doc comment sits on `seededCategoryColours`.
- **Fix direction:** Use `selectOnly` with `count()`, and move the comment to `recurringCursorKey`.
- **Status:** open

---

## U — UI screens and widgets

### U-1 · Medium · correctness — Re-running onboarding resets the AI provider and its URL
- **Where:** `lib/features/settings/widgets/about_section.dart:41`; `lib/features/onboarding/onboarding_screen.dart:189-193`, `:227-229`.
- **What:** `_resetOnboarding` sets `onboardingCompleteNotifier` to false and *then* navigates. `OnboardingScreen` uses that same flag to tell a revisit from a first run, so it always sees a first run, and the availability check replaces the provider with `suggestedDefault` and its default URL. `_finish` then saves them. The comment at `:175-180` says this is exactly what must not happen.
- **Impact:** Settings → About → Show onboarding, then Next through the pages, quietly switches a Claude, ChatGPT or remote-Ollama user to Apple Intelligence or `localhost` Ollama. On a phone the AI tab can disappear.
- **Fix direction:** Decide "revisit" from something not cleared before navigating, such as a route parameter or the flag read before it is reset.
- **Status:** open

### U-2 · Medium · privacy — The Bitcoin routing banner describes unsaved text, not the saved server
- **Where:** `lib/features/settings/widgets/bitcoin_servers_section.dart:141-144`, `:188-198`.
- **What:** The banner reads the text field on every keystroke. Typing any URL flips it to "All data routed through your server… mempool.space and CoinGecko are never contacted" before Save, including for a URL that Save will reject.
- **Impact:** The user is told lookups are private while syncs still go to mempool.space.
- **Fix direction:** Drive it from the saved `esploraBaseUrl`, or label the live preview "after saving". See also B-9.
- **Status:** open

### U-3 · Medium · privacy — Onboarding accepts an unusable Esplora URL without saying so
- **Where:** `lib/features/onboarding/onboarding_screen.dart:104`.
- **What:** `saveSettings`' null return ("unusable, using mempool.space") is ignored. Settings warns about the same case (`bitcoin_servers_section.dart:56-59`).
- **Impact:** Someone who mistypes their own node's URL during onboarding has every wallet address sent to mempool.space, and is never told.
- **Fix direction:** Check the result and warn, or stay on the page, as Settings does.
- **Status:** open

### U-4 · Medium · privacy — Stored API keys are preloaded into Settings and shown with one tap
- **Where:** `lib/features/settings/widgets/ai_provider_section.dart:101-104`, `:444`, `:457-467`.
- **What:** Each provider's key is read from the keychain into a text field as soon as Settings opens (the sections keep their state), and the eye icon reveals it with no re-authentication. The screenshot side of this is P-1.
- **Impact:** Anyone holding an unlocked phone can read the user's paid API keys.
- **Fix direction:** Show a "key saved" placeholder instead of the key, and gate reveal behind device authentication.
- **Status:** open

### U-5 · Medium · performance — The import screen creates its Drift stream in `build()`
- **Where:** `lib/screens/import/import_file_screen.dart:179`, `:402-415`, `:689-701`.
- **What:** `stream: app.importService.watchSources()` sits in `build`, and during an AI import every token calls `setState`. So each token re-subscribes and re-queries `import_sources`, the bug class `tab_stream_test` pins for the tabs. The per-token rebuild itself is A-10.
- **Impact:** Hundreds of queries and full rebuilds per import, and jank while the model streams.
- **Fix direction:** Create the stream once in `initState`, and give the streamed text its own listenable.
- **Status:** open

### U-6 · Medium · reliability — Several saves and deletes fail without telling the user
- **Where:** `transaction_edit_sheet.dart:155-243` (try/finally, no catch anywhere in the file), `:269`, `:301`; `import_preview_screen.dart:45-75`; `import_column_mapper_screen.dart:137-178`; `import_source_setup_screen.dart:48-57`; `danger_zone_section.dart:43-67`; `transactions_screen.dart:659` (`deleteById` neither awaited nor caught); `wallet_history_section.dart:86`, `:97` (an exception leaves `_busy` set).
- **What:** Exceptions become unhandled async errors. The spinner resets, or sticks, and nothing is shown.
- **Impact:** A failed import or edit looks like nothing happened. A failure partway through "Reset all data" leaves a half-reset app.
- **Fix direction:** Catch and show the error, as `AddTransactionSheet` and the categories sheet already do.
- **Status:** open

### U-7 · Medium · accessibility — Rows overflow at large text sizes
- **Where:** `lib/features/stack/widgets/stack_hero.dart:104-115`; `stack_goal_card.dart:122-145`, `:166-201`; `dca_simulator.dart:101-145`; `import_file_screen.dart:1111-1164`; `transactions_screen.dart:162-190` (AppBar); `ai_chat_screen.dart:962` (model dropdown without `isExpanded`).
- **What:** Unflexed text beside `Spacer`s, chips or buttons. The dashboard hero was moved to a `Wrap` for exactly this.
- **Impact:** Overflow stripes and clipped figures for users with large accessibility text.
- **Fix direction:** Use `Flexible`, `Wrap` or `ShrinkToFit`, as the dashboard does.
- **Status:** open

### U-8 · Low · correctness — Switching currency briefly mislabels the price, or keeps it mislabelled if the write fails
- **Where:** `lib/features/settings/widgets/general_section.dart:86-100`; `onboarding_screen.dart:76-85`.
- **What:** The notifier is set, then the write is awaited, and only then is `switchCurrency` called. Until that call the old currency's price sits under the new label, and if the write throws, `switchCurrency` never runs.
- **Impact:** Fiat figures are wrong by the exchange rate for one write, or for the session.
- **Fix direction:** Call `switchCurrency` with the notifier change, and persist afterwards.
- **Status:** open

### U-9 · Low · correctness — Budget edit field shows the wrong currency symbol when there is no rate
- **Where:** `lib/features/budgets/widgets/set_budget_sheet.dart:199-200` vs `:90-93`.
- **What:** The prefix is always the display currency's symbol, but with no rate the amount shown and saved is in the budget's own currency.
- **Impact:** A USD budget viewed in GBP reads "£ 300.00" and is saved as $300.
- **Fix direction:** Use the symbol of the currency that will actually be saved.
- **Status:** open

### U-10 · Low · correctness, performance — The stack chart misrepresents time and redraws on every price tick
- **Where:** `lib/features/stack/widgets/stack_history_chart.dart:30-41`, `:99-101`; `stack_screen.dart:210-227`.
- **What:** The x-axis indexes only months with activity, so a two-year gap is one step. The 3M/6M/1Y filters drop the balance carried in, so a flat stack shows "Not enough data". The chart sits under the price listener but never uses the price.
- **Impact:** A misleading chart, and pointless rebuild work on each tick.
- **Fix direction:** Time-based x values with idle months filled, seed each window with the prior balance, and lift the chart out of the listener.
- **Status:** open

### U-11 · Low · correctness — The date picker asserts on imported dates outside its range
- **Where:** `lib/features/transactions/widgets/transaction_edit_sheet.dart:127-132`.
- **What:** `firstDate: 2009-01-03`, `lastDate: tomorrow`, while `initialDate` comes from the row.
- **Impact:** Editing a pre-2009 fiat row or a future-dated bank row throws in debug and misbehaves in release.
- **Fix direction:** Clamp `initialDate`, or widen the range for fiat rows.
- **Status:** open

### U-12 · Low · accessibility — Sheets that don't scroll
- **Where:** `manage_wallets_sheet.dart:140`; `transactions_screen.dart:383` (filter sheet); `stack_goal_card.dart:272` (`SetGoalSheet`); `ai_chat_screen.dart:1076`.
- **What:** Plain `Column`s with no scroll.
- **Impact:** With many wallets or categories, or a large font, the bottom rows and the Apply button can't be reached.
- **Fix direction:** Wrap them as `SetBudgetSheet` does.
- **Status:** open

### U-13 · Low · accessibility — Low-contrast text the `legibleAccent` pass missed
- **Where:** `stack_hero.dart:131-144`; `stack_goal_card.dart:127`, `:213-215`; `dca_simulator.dart:263`; `analytics_screen.dart:590`; `import_file_screen.dart:986`, `:1025`; `import_preview_screen.dart:261`; `ai_chat_screen.dart:1179`.
- **What:** Raw green, orange or blue used as text colour (the codebase's own figures: 3.4:1 and 2.3:1 on white).
- **Impact:** Hard to read in light mode.
- **Fix direction:** Route them through `context.legibleAccent` / `bitcoinOrangeText`.
- **Status:** open

### U-14 · Low · accessibility — Tap targets under 48 px
- **Where:** `transactions_screen.dart:168-189` (compact AppBar icons, 40 px), `:508`; `transaction_edit_sheet.dart:353`; `import_file_screen.dart:1033`, `:1148`, `:1154`.
- **What:** `VisualDensity.compact` and `shrinkWrap` on touch targets.
- **Impact:** Small controls are hard to hit.
- **Fix direction:** Drop them on touch platforms.
- **Status:** open

### U-15 · Low · performance, privacy — Opening Settings calls the AI provider even if Servers is never opened
- **Where:** `lib/features/settings/settings_screen.dart:82`; `ai_provider_section.dart:78-79`, `:109`, `:125-155`.
- **What:** `maintainState: true`, added in #54 so collapsed sections keep their state, also builds them while collapsed. So `AiProviderSection.initState` runs `listModels()` (a request to the hosted provider with the user's key) and the platform probes on every Settings open. The old single state class did the same, but now it's a cost of something meant only to preserve text.
- **Impact:** Changing the theme makes a request to the AI provider, and every Settings open is slower.
- **Fix direction:** Defer the probes until the section first expands.
- **Status:** open

### U-16 · Low · privacy — Copied chat answers stay on the clipboard
- **Where:** `lib/features/ai_chat/ai_chat_screen.dart:546`.
- **What:** A long-press copies an answer full of financial figures, and it is never cleared. Leftover statement photos are A-7.
- **Impact:** Figures remain readable by any app that reads the clipboard.
- **Fix direction:** Clear after a timeout, or say so when copying.
- **Status:** open

### U-17 · Low · performance — Search reruns the whole filter and grouping on every keystroke
- **Where:** `lib/features/transactions/transactions_screen.dart:219`, `:285`, `:527-532`.
- **What:** A case-folded filter over every transaction, then grouping and sorting by day, on each character, with no debounce.
- **Impact:** Lag on large histories.
- **Fix direction:** Debounce, and memoise the grouping per data or filter change.
- **Status:** open

### U-18 · Low · correctness — The price chip's age label can stay at "just now"
- **Where:** `lib/shared/widgets/btc_price_chip.dart:71`, `:130`.
- **What:** The age is computed only when the chip rebuilds, and a failed fetch doesn't rebuild it.
- **Impact:** An offline user sees "just now" on an hours-old price.
- **Fix direction:** Tick it periodically, or rebuild on each fetch attempt.
- **Status:** open

### U-19 · Low · reliability — Electrum "Save and test" replaces a working server before testing the new one
- **Where:** `lib/features/settings/widgets/wallet_history_section.dart:86-91`.
- **What:** `saveSettings` runs before the test, so if Electrum is already the source, a failed test leaves the broken host in use.
- **Impact:** One typo breaks syncing until it is noticed.
- **Fix direction:** Test the candidate first, and persist only on success.
- **Status:** open

### U-20 · Low · reliability — Onboarding's finish has no double-tap guard or error handling
- **Where:** `lib/features/onboarding/onboarding_screen.dart:56-65`, `:74-170`.
- **What:** "Get Started" can run `_finish` twice at once, and a keychain or database error is not caught.
- **Impact:** Duplicate writes, or a user stuck on the last page with no message.
- **Fix direction:** Guard against a second tap, and show errors.
- **Status:** open

### U-21 · Low · reliability — `setState` can run after dispose in the insight flow
- **Where:** `lib/features/dashboard/dashboard_screen.dart:136-139` → `:157`.
- **What:** After `await isInsightStale()`, `_generateInsight` calls `setState` without checking `mounted`.
- **Impact:** Rare, since the tab stays alive, but it throws when it happens.
- **Fix direction:** Check `mounted`.
- **Status:** open

### U-22 · Low · maintainability, reliability — Duplicated colour parsers that throw on bad data
- **Where:** `manage_wallets_sheet.dart:219-222`; `categories_sheet.dart:128-131`, `:433-439`, `:533-535`, `:613-674`; `add_wallet_sheet.dart:547`; `transaction_list_item.dart:173-202`; plus five more `_parseColor` copies.
- **What:** `int.parse` throws on a malformed colour, which a restored database could hold, and two icon maps are duplicated.
- **Impact:** A bad colour red-screens a whole sheet.
- **Fix direction:** Use `CategoryPalette.parseHex` everywhere, and share one icon map.
- **Status:** open

---

## P — Native configuration, CI and dependencies

### P-1 · Medium · security — No app-switcher or screenshot protection on any platform
- **Where:** `android/app/src/main/kotlin/app/satsstack/satsstack/MainActivity.kt:6`; `ios/Runner/AppDelegate.swift:6`. Nothing anywhere uses `FLAG_SECURE` or a lifecycle-driven privacy screen (checked).
- **Impact:** The Recents thumbnail and the iOS app-switcher snapshot capture balances, the stack, transactions and AI chat. Screen recording and screenshots capture everything.
- **Fix direction:** `FLAG_SECURE` on Android, at least as a setting, and a cover view on iOS `sceneWillResignActive` or Flutter `inactive`.
- **Status:** open

### P-2 · Medium · privacy — iOS database goes into iCloud and device backups; Android deliberately excludes it
- **Where:** `lib/core/database/database.dart:483` (Documents directory). There is no iOS entitlements file, and nothing sets `NSURLIsExcludedFromBackupKey` (checked). Compare `android/app/src/main/res/xml/data_extraction_rules.xml:16-25`.
- **Impact:** The plaintext financial database is uploaded to iCloud Backup, readable by Apple unless Advanced Data Protection is on, and lands in unencrypted Finder backups. The two platforms contradict each other.
- **Fix direction:** Decide one backup policy for both platforms. On iOS, exclude the database, journal and `.bak` from backup, or document iCloud as intended. Consider `NSFileProtectionComplete`.
- **Status:** open

### P-3 · Medium · supply-chain — GitHub Actions pinned to mutable tags, including those holding secrets
- **Where:** `.github/workflows/claude.yml:41-48`, `claude-code-review.yml:37-47`, `ci.yml:28`, `:30`, `:89`, `:104`, `:148`, `:152`.
- **What:**
  - `anthropics/claude-code-action@v1` receives the OAuth token and `id-token: write`.
  - Third-party `subosito/flutter-action@v2` and `maxim-lobanov/setup-xcode@v1.7.0` run on tags.
  - The plugin marketplace is fetched from a default branch at run time.
  - `checkout` keeps its credentials.
  - There is no Dependabot.
- **Impact:** A moved tag or a compromised upstream runs new code with the tokens, and no commit here shows it.
- **Fix direction:** Pin each action to a commit SHA, set `persist-credentials: false`, and add Dependabot for `github-actions` and `pub`.
- **Status:** open

### P-4 · Medium · supply-chain — End-of-life SQLite libs, a discontinued keychain backend, wide version lag
- **Where:** `pubspec.yaml:15`, `:38`, `:57`, `:60`, `:71`, `:74`; `pubspec.lock:935`.
- **What:**
  - `sqlite3_flutter_libs` 0.5.42 is end of life (latest `0.6.0+eol`). It ships the native SQLite that holds all data and comes through the held `drift_flutter ^0.2.8`.
  - `flutter_secure_storage_macos`, which holds the macOS API keys, is discontinued.
  - Syncfusion PDF, which parses untrusted PDFs, is seven majors behind (28 against 35).
  - Further lag: notifications 19 → 22, `file_picker` 10 → 13, `go_router` 16 → 18. Sixty-three packages are locked below versions they could already move to.
- **Impact:** SQLite fixes stop arriving for the most sensitive native code, and each month of lag makes the upgrade bigger.
- **Fix direction:**
  - Plan `drift_flutter` 0.3 / `sqlite3` 3.x as its own change; it also unblocks SQLCipher.
  - Plan `flutter_secure_storage` 10/11 with a key-migration test.
  - Run `flutter pub upgrade` within the current constraints regularly.
- **Status:** open

### P-5 · Medium · privacy — ML Kit GenAI may bring Google's telemetry transport into Android builds
- **Where:** `android/app/build.gradle.kts:94` (`com.google.mlkit:genai-prompt:1.0.0-beta2`).
- **What:** The Gradle cache holds `com.google.android.datatransport` (`transport-backend-cct`, `transport-runtime`) next to ML Kit common, which is ML Kit's usual path for reporting usage to Google. Whether it is in the release classpath is unverified.
- **Impact:** A local-first app may report usage to Google on every Android install, including installs that never use Gemini Nano. That affects the Play Data safety form and the app's privacy copy.
- **Fix direction:** Check `:app:dependencies --configuration releaseRuntimeClasspath`. Then exclude it, disable it, or declare it.
- **Status:** open

### P-6 · Low · reliability — The test network guard misses raw sockets
- **Where:** `test/flutter_test_config.dart:14-27`.
- **What:** It overrides only `HttpClient`, while Electrum uses `Socket` and `SecureSocket` directly. Its `startsWith('127.')` check also accepts a hostname like `127.example.com`.
- **Impact:** A test could reach a real Electrum server without anyone noticing.
- **Fix direction:** Add `IOOverrides` for sockets, compare parsed IP literals, and test the raw-socket case.
- **Status:** open

### P-7 · Low · privacy — No privacy manifest for the app itself
- **Where:** `ios/Runner/` and `macos/Runner/`. There is no `PrivacyInfo.xcprivacy` outside Pods.
- **Impact:** The App Store privacy label may understate collection, since financial context goes to the hosted AI providers when one is chosen.
- **Fix direction:** Add a Runner manifest declaring no tracking, the data the hosted-AI path sends, and any required-reason APIs.
- **Status:** open

### P-8 · Low · privacy — Amounts in notifications, including on the lock screen
- **Where:** `notification_service.dart:100-104`, `:127-131`, `:152-156`, `:243-250`.
- **What:** Bodies include budget overspends and "You've stacked N sats ≈ $X". No Android `visibility` or `publicVersion` is set.
- **Impact:** Holdings show on a locked or shared screen, a physical-security concern for Bitcoin.
- **Fix direction:** Private visibility with a generic public version, or no amounts in the text.
- **Status:** open

### P-9 · Low · reliability — CI never builds Apple release configs; no job timeouts; Linux/Windows unbuilt
- **Where:** `.github/workflows/ci.yml:166-172`; `integration_test/`; `linux/`, `windows/`.
- **What:**
  - iOS and macOS are built as debug only.
  - The three integration tests never run.
  - No job has `timeout-minutes`.
  - `linux/` and `windows/` are tracked but never built.
- **Impact:** Release-only Apple regressions can ship, and a hung macOS job burns hours.
- **Fix direction:** Unsigned `--release` builds for both Apple targets, and timeouts. Delete or build Linux and Windows.
- **Status:** open

### P-10 · Low · security — macOS: no hardened runtime, and no local-network purpose string
- **Where:** `macos/Runner.xcodeproj/project.pbxproj:560`, `:636`, `:692`; `macos/Runner/Info.plist`.
- **What:** The build is ad-hoc signed with no hardened runtime. iOS declares `NSLocalNetworkUsageDescription` and macOS doesn't, though macOS users can point the app at LAN servers.
- **Impact:** The app can't be notarised (already tracked in `TODO.md`). LAN behaviour on macOS 15+ without the string is unverified.
- **Fix direction:** Do both when the macOS bundle id is registered.
- **Status:** open

### P-11 · Low · maintainability — Stale configuration comments; strict analyzer modes off
- **Where:** `analysis_options.yaml:50-51`; `android/app/build.gradle.kts:37`.
- **What:**
  - `avoid_dynamic_calls` is on, but the "Considered and not enabled" list still describes it as 43 sites tracked in `TODO.md`. It was left behind by #53.
  - The template `// TODO: Specify your own unique Application ID` is still there.
  - `strict-casts`, `strict-inference` and `strict-raw-types` are all off.
- **Fix direction:** Delete the stale lines, and consider the strict modes.
- **Status:** open

### P-12 · Low · security — Committed test TLS key (acceptable, but flagged by scanners)
- **Where:** `test/fixtures/electrum_test_key.pem`, `electrum_test_cert.pem`.
- **What:** A self-signed `localhost` pair valid until 2126, used only by `wallet_history_section_test` on loopback. The app never trusts it.
- **Impact:** No real exposure, but secret scanners will flag it.
- **Fix direction:** Generate it at test time, or add a scanner allowlist and a README line in `test/fixtures/`.
- **Status:** open

---

## T — Tests

### T-1 · Low · maintainability — Large screens have no tests at all
- **Where:** from `flutter test --coverage`, 57 % of lines overall. At 0–3 %:
  - `import_file_screen.dart` (2 of 507 lines)
  - `ai_chat_screen.dart` (15 of 501)
  - `add_transaction_sheet.dart` (0 of 319)
  - `analytics_screen.dart` (2 of 295)
  - `ai_provider_page.dart` (0 of 200)
  - `import_preview_screen.dart` (0 of 193)
  - `import_column_mapper_screen.dart` (0 of 173)
  - the onboarding screens (about 1 %)
  - `import_summary_screen.dart` (0 of 92)
  - `on_device_ai_section.dart` (0 of 56)
- **Impact:** The screens where the user adds money and imports statements can regress unnoticed. Several findings above (A-5, A-6, A-10, A-18) live in them.
- **Fix direction:** Pin each with widget tests before fixing what is in them, as was done for Settings in #54.
- **Status:** open

---

## Checked and found clean

- **Runtime:** a fresh install makes no network connection before onboarding is finished.
- **Bitcoin:**
  - BIP32 derivation (the HMAC split, the IL ≥ n check, point at infinity), hash160, and the P2PKH, P2SH-P2WPKH and bech32 v0 encodings.
  - Extended private keys refused before anything is stored. Gap limit and change-chain netting.
  - Electrum scripthash order, SegWit parsing, the coinbase exclusion and the prevout bounds check.
  - TLS pinning: checked only after CA failure, pinned to the leaf's SHA-256, kept only for the same server. Timeouts exist on every connect and call.
  - No wallet request is ever made without the user's action.
- **AI:**
  - Consent scoped per provider and per server (`scheme://host:port`), withdrawable, and asked again on a URL change.
  - Backend privacy derived from the URL and failing closed.
  - API keys never in URLs, the database or logs; auth-error bodies that echo keys suppressed. Transcripts not stored.
  - SSE parsing handles split frames and `[DONE]` variants. Idle timeouts close the stream.
  - No regex at backtracking risk. Statement text can shape only the model's JSON, which the user reviews, and there is no tool calling.
- **Data:**
  - Migrations atomic, idempotent and selecting only the columns they use.
  - Indexes match the queries. Budget upsert and category rename are transactional.
  - Dedup and recurring hashes use fields that can't change. Months are half-open, recurring dates are DST-safe, and FX returns null without a rate.
  - Export via `VACUUM INTO`. Nothing logs financial data.
- **Platform:**
  - The Android manifest declares only `INTERNET`, with only the launcher exported. Android backups exclude the database and keys.
  - The release isn't debug-signed, and keystores are gitignored.
  - iOS purpose strings match real use, and keychain items are `this_device`. macOS release entitlements are minimal.
  - No real secrets in the tree or in any of the 197 commits.
  - CI is read-only, uses `--enforce-lockfile`, holds analyze and format at zero, runs a DST time-zone test pass, and has no `pull_request_target`.
