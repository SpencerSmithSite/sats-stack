# Agent Access — MCP Server + Skill

**Status:** Research complete, not started
**Researched:** 2026-08-09
**Goal:** Let external AI agents (Claude Desktop, Claude Code, and any MCP-capable
third-party agent) read and write Sats Stack data — e.g. *"How much did I spend on
dining out last month?"* and *"I just spent $50 at XYZ store, log it."*

---

## 1. Findings that change the shape of the idea

Four things came out of the research that the original framing got wrong or didn't
account for. They're listed first because each one removes an option.

### 1.1 There is no "MCP 2.0"

MCP is **date-versioned, not semver**. The latest spec revision is **`2026-07-28`**,
published 2026-07-28 — the largest revision since MCP launched. The "2.0" label in
circulation comes from the *SDK* major-version betas released alongside it (Python
`2.0.0b1`, TypeScript v2, C# `2.0.0-preview.1`), which press coverage conflated with
the protocol.

What `2026-07-28` actually changed — it makes the protocol **stateless**:

| Change | Effect |
|---|---|
| `initialize` handshake removed | Every request self-describes via `_meta` (protocol version, client capabilities) |
| `Mcp-Session-Id` removed | No session lifecycle to manage |
| New required `server/discover` RPC | Servers advertise versions/capabilities/identity |
| `subscriptions/listen` | Replaces the SSE GET stream and `resources/subscribe` |
| **Multi Round-Trip Requests (MRTR)** | Replaces server-initiated sampling/elicitation/roots. A result returns `resultType: "input_required"` + `inputRequests`; the client retries with `inputResponses` |
| `Mcp-Method` / `Mcp-Name` HTTP headers | Gateway routing without body inspection |
| Cacheable list results | `ttlMs` + `cacheScope` (`public`/`private`) required on `*/list` and `resources/read` |
| **Deprecated:** Roots, Sampling, Logging, legacy HTTP+SSE, OAuth DCR (→ CIMD) | 12-month minimum deprecation window |

**Relevance here: mostly none.** For a local stdio server almost all of this is
invisible — stdio is untouched, and the OAuth/CIMD hardening only applies to
network-reachable servers. The two parts that *do* matter:

- **MRTR** is how you implement "are you sure you want me to log this?" confirmations.
- **Structured output** (`outputSchema` + `structuredContent`, from `2025-06-18`) is
  what makes tool results machine-actionable instead of prose the agent has to parse.

### 1.2 A Skill alone cannot reach the database

Agent Skills are markdown + optional bundled scripts, loaded progressively. On the
hosted surfaces (Claude API, claude.ai) skills execute in a **sandboxed container with
no network access and no access to your Mac's filesystem**. So a Skill can never be the
data-access mechanism.

The split is forced, and it happens to be the officially documented composition pattern:

- **MCP server** = the *connection*. Real DB access, typed tools.
- **Skill** = the *procedural knowledge*. How to use those tools correctly.

The Skill is genuinely worth building, though — it's where the domain conventions live
that an agent will otherwise get wrong:

- The category is `"Food & Dining"`, not `"dining"` or `"Food"`
- `amountSats` is negative for spending, positive for income
- Manual entries need `salt = microsecondsSinceEpoch`; CSV re-imports need `salt = ''`
- Manual transactions require a wallet FK (default wallet: `"My Account"`)
- "Last month" means calendar month, and the app's month boundaries are local-time

**Portability is real.** Agent Skills is now an open standard at
[agentskills.io](https://agentskills.io) with cross-vendor adoption (Cursor, GitHub
Copilot, VS Code, Gemini CLI, OpenAI Codex, Goose, OpenHands, JetBrains Junie, and
others). But **only the 6-field frontmatter subset is portable**: `name`, `description`,
`license`, `compatibility`, `metadata`, `allowed-tools`. Claude Code's extra fields
(`when_to_use`, `argument-hint`, `context: fork`, `hooks`, …) cause a hard packaging
error if included in a skill destined for claude.ai or the Skills API.

### 1.3 iOS is structurally dead for this. Desktop is the only real target.

Not "harder" — blocked by OS design:

- **Direct file access to the app's container from another process**: impossible on iOS
  and Android without a jailbreak/root. The app declares no `UIFileSharingEnabled`, so
  the DB isn't even visible to the Files app.
- **App hosts a local HTTP server**: iOS suspends background execution (~30s after
  backgrounding), there's no `UIBackgroundModes` entry today, and no legitimate
  background mode covers "run an arbitrary HTTP server." Abusing one risks rejection.
- Android is asymmetric — a foreground service with a persistent notification is a
  legitimate pattern iOS doesn't offer — but direct file access is still root-only.

**Conclusion: build for macOS first.** Mobile gets, at best, a read-only snapshot
fallback (§5, Phase 5) and that's a deliberate later decision, not an oversight.

### 1.4 The database is not in WAL mode — fix this before anything else

Measured directly on the live DB:

```
$ sqlite3 ~/Library/Containers/com.satsstack.satsStack/Data/Documents/sats_stack_db.sqlite \
    "pragma journal_mode; pragma user_version;"
delete
5
```

`journal_mode = delete` means a rollback journal, where **a writer takes an exclusive
lock on the entire database**. A sidecar process writing while the app is open will
either block or fail with `SQLITE_BUSY`. WAL mode allows one writer concurrent with
many readers, which is exactly the access pattern this feature creates.

This is a one-line fix in [`database.dart`](../lib/core/database/database.dart):

```dart
QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'sats_stack_db',
    native: const DriftNativeOptions(shareAcrossIsolates: true),
    // ...verify the exact option name against drift_flutter ^0.2.8 —
    // otherwise set the pragma in a setup callback:
    //   setup: (db) => db.execute('PRAGMA journal_mode=WAL;'),
  );
}
```

**Do this in Phase 0 and confirm with the pragma above.** Everything downstream assumes it.

---

## 2. Verified ground truth

| Fact | Value | How verified |
|---|---|---|
| DB open call | `driftDatabase(name: 'sats_stack_db')`, no path override | [database.dart:153](../lib/core/database/database.dart) |
| drift_flutter default dir | `getApplicationDocumentsDirectory()` | pub.dev drift_flutter docs |
| **macOS bundle id** | **`com.satsstack.satsStack`** | `macos/Runner/Configs/AppInfo.xcconfig:11` |
| iOS bundle id | `app.satsstack.SatsStack` | CLAUDE.md |
| **Live macOS DB path** | `~/Library/Containers/com.satsstack.satsStack/Data/Documents/sats_stack_db.sqlite` | `find` on this machine |
| `schemaVersion` | **5** (CLAUDE.md says 3 — stale) | `pragma user_version` = 5 |
| `journal_mode` | **`delete`** (not WAL) | `pragma journal_mode` |
| macOS App Sandbox | Enabled in Debug + Release | `macos/Runner/*.entitlements` |
| `network.server` entitlement | **Debug only — absent from Release** | Both entitlements files, diffed |
| Tables | 11 + `sqlite_sequence` | `sqlite_master` |
| Full Disk Access needed? | **Not for a plain `sqlite3` read on this machine** — but the reading process may already hold FDA. Re-test with a fresh, unprivileged binary. | Read the container DB successfully with system `sqlite3` |

> ⚠️ The macOS bundle id (`com.satsstack.satsStack`) differs from the iOS one
> (`app.satsstack.SatsStack`). Any hardcoded path must use the macOS id — and better,
> shouldn't hardcode at all (see the handshake file in Phase 0).

### Dart MCP SDK options (both verified on pub.dev, 2026-08-09)

| | `dart_mcp` | `mcp_dart` |
|---|---|---|
| Publisher | **labs.dart.dev** (official Dart team, verified) | leehack.com (community, verified) |
| Latest | 0.5.2 (~41 days ago) | 2.4.0 (~9 days ago) |
| Likes / points / downloads | 82 / 150 / 290k | 75 / 160 / 177k |
| Newest spec supported | 2024-11-05 → 2025-11 era | **2026-07-28** + legacy fallback, 3 protocol profiles |
| Transports | **stdio only** (HTTP "may come in the future") | stdio + Streamable HTTP + legacy SSE, server & client |
| Self-description | "still experimental and is likely to evolve quickly" | "complete core client/server wire surface" of 2026-07-28 |
| License | BSD-3 | MIT |

**Recommendation: start with `dart_mcp`.** stdio-only is not a limitation for this use
case — Claude Desktop and Claude Code launch local MCP servers as a subprocess and speak
JSON-RPC over stdio; that *is* the first-class local integration path. Official-package
status matters more than spec recency for a local server that never touches OAuth or
HTTP. Keep `mcp_dart` as the fallback if `dart_mcp`'s experimental churn becomes painful
or if Streamable HTTP is ever needed.

---

## 3. Architecture decision

Four options were evaluated. Summary:

| | A. Sidecar (Node/Python) reads SQLite | B. App hosts HTTP server | **C. Dart MCP binary, shared schema** | D. Export snapshot |
|---|---|---|---|---|
| macOS | Yes (FDA hurdle unverified) | Yes, needs Release entitlement re-added | **Yes** | Yes |
| iOS | Dead | Dead in practice | Dead | Yes (stale, read-only) |
| Android | Root only | Foreground service, unverified | Root only | Yes (stale, read-only) |
| Works when app closed | Yes | **No** | **Yes** | Reads only |
| Schema-drift risk | **High, permanent, cross-language** | Low | **Very low (shared code)** | Medium |
| New attack surface | Raw DB access, no auth boundary | **Listening socket** | None (stdio subprocess) | None |
| Effort | Medium | Medium-high | Medium | Low |

### Chosen: **Option C — a Dart-native MCP server binary, stdio, sharing the Drift schema package**

Reasoning:

1. **It works when the app is closed.** Claude launches the binary, it opens the SQLite
   file, answers, exits. No "is the app running?" precondition.
2. **It eliminates schema drift.** A Node or Python sidecar would have to re-implement
   Drift's generated schema — column names, `TypeConverter` encodings, migration
   history — in another language, in another repo, and keep it in lockstep with every
   future migration. Option C compiles the *same* `database.g.dart`.
3. **No entitlements fight and no new socket.** stdio needs neither
   `com.apple.security.network.server` nor a background-execution story. Option B would
   add a permanent local listening socket to an app whose entire pitch is "no server, no
   cloud, on-device" — that's a positioning cost as well as a security one.

**Option B is explicitly ruled out**, not deferred. On desktop it buys nothing C doesn't
already have, and on mobile it's a dead end.

### Cross-cutting: typed tools, never raw SQL

Whichever transport wins, the exposed surface must be a **narrow set of typed
operations**, not `execute_sql` or table CRUD. This is a financial ledger:

- Business rules stay enforced in code the agent can't bypass — dedup hashing, category
  validation, wallet FK, recurring-series anchors, sats/fiat conversion at the right
  historical price.
- The tool contract becomes the stable interface, so Drift migrations don't break agents.
- Blast radius is bounded. An LLM improvising `UPDATE transactions SET ...` against real
  financial history is a foreseeable corruption source.

The tool layer should **wrap the existing services** (`TransactionService`,
`DashboardService`, `BudgetService`, `CategoryService`) rather than reimplement queries
against raw tables.

---

## 4. Proposed tool surface

### Read (Phase 1)

| Tool | Args | Returns |
|---|---|---|
| `list_transactions` | `from`, `to`, `category?`, `walletId?`, `source?`, `limit=50` | id, date, description, amountSats, amountFiat, currency, category, wallet, source |
| `get_spending_summary` | `from`, `to`, `groupBy: category\|wallet\|month` | totals per group, fiat + sats |
| `get_dashboard` | `month` | income, spending, surplus, stack total, per-wallet breakdown |
| `get_budgets` | `month` | per-category budget, spent, remaining, % used |
| `get_stack` | — | total sats, fiat value, goal, % to goal, projected date |
| `list_categories` | — | name, color, icon, isSystem |
| `list_wallets` | — | id, label, type, color |
| `get_btc_price` | `currency?`, `date?` | spot, or historical from `BtcPriceHistory` |

Every tool declares an `outputSchema` and returns `structuredContent`. List results get
`ttlMs` + `cacheScope: "private"` — this is personal financial data and must never land
in a shared cache.

### Write (Phase 2)

| Tool | Notes |
|---|---|
| `add_transaction` | `description`, `amountFiat`, `currency?`, `date?` (default today), `category?`, `walletId?` (default the manual wallet), `notes?`. Computes `amountSats` from the price at `date`, and `dedupHash` with `salt = microsecondsSinceEpoch`. Sign convention applied server-side. |
| `update_transaction` | `id` + changed fields. Must preserve the existing `dedupHash`, matching [transaction_edit_sheet.dart:172](../lib/features/transactions/widgets/transaction_edit_sheet.dart). |
| `delete_transaction` | `id`. **MRTR confirmation required.** |
| `set_budget` | `category`, `amountFiat`, `period` |

**Safety model:**

- Server runs **read-only by default**. Writes require an explicit `--allow-writes` flag
  in the MCP config, so the user opts in at install time.
- Deletes and bulk operations use MRTR (`resultType: "input_required"`) to force a
  human confirmation turn.
- Every mutation is appended to a local audit log (`~/.satsstack-mcp/audit.jsonl`) —
  cheap, and the only way to answer "what did the agent change?"
- Never expose `AiConversations` or the xpub values in `Wallets` unless explicitly asked.
  An xpub leaks the full transaction history of a wallet to whoever holds it.

---

## 5. Phased plan

### Phase 0 — Prerequisites *(small, do first)*
- [ ] Switch DB to **WAL** mode; verify with `pragma journal_mode`
- [ ] App writes its resolved absolute DB path to a handshake file on startup
      (`~/Library/Application Support/SatsStack/db_path.txt`) so the binary never
      hardcodes sandbox path conventions or bundle ids
- [ ] Fix stale CLAUDE.md facts: `schemaVersion` is **5**, not 3; document the 3 newer
      import tables (`ImportSources`, `ImportedTransactions`,
      `DescriptionCategoryMappings`) and the macOS-vs-iOS bundle id split

### Phase 1 — Spike *(1–2 days, no product commitment)*
- [ ] Extract `lib/core/database/` into a standalone `packages/sats_stack_data` Dart
      package, consumed by the app via a path dependency. Use `package:drift/native.dart`
      (not `drift_flutter`, which is Flutter-only) in the CLI.
- [ ] Throwaway `dart compile exe` CLI that opens the live DB and prints a spending
      summary. Confirms the package split works and that the AOT binary can read the file.
- [ ] **Test SQLite version parity.** The app bundles its own build via
      `sqlite3_flutter_libs` (transitive); a bare Dart binary loads the *system*
      `libsqlite3.dylib` (macOS system version here: 3.54.0). Low risk given the simple
      schema — no FTS, JSON1, or extensions in use — but verify rather than assume.
- [ ] **Re-test Full Disk Access** with a freshly compiled, unsigned binary. Reading the
      container succeeded here with system `sqlite3`, but that process may already hold
      FDA. This determines whether install UX is "just works" or "grant FDA to this CLI."

### Phase 2 — Read-only MCP server
- [ ] Add `dart_mcp`, implement the §4 read tools over stdio
- [ ] `outputSchema` + `structuredContent` on every tool; `cacheScope: "private"`
- [ ] Test end-to-end in Claude Desktop and Claude Code, **app open and app closed**

### Phase 3 — Writes
- [ ] `add_transaction` reusing `HashUtils.transactionDedupHash` and the existing
      service-layer validation
- [ ] `--allow-writes` gate, MRTR confirmation on destructive ops, audit log
- [ ] **Concurrency test:** edit a transaction in the app while the binary writes.
      This is the test that proves the Phase 0 WAL change actually worked.

### Phase 4 — The Skill
- [ ] `skills/sats-stack/SKILL.md`, **6-field portable frontmatter only**
- [ ] Encode the conventions: exact category names, sign convention, dedup salt rules,
      wallet FK, month-boundary semantics, fully-qualified tool names
      (`sats-stack:list_transactions`) so it works with multiple MCP servers connected
- [ ] Keep under 500 lines / ~5k tokens; reference files one level deep from SKILL.md

### Phase 5 — Distribution
- [ ] Package as **`.mcpb`** (MCP Bundle — formerly Anthropic's DXT, moved to the
      `modelcontextprotocol` GitHub org in Nov 2025 and now client-agnostic). One-click
      install, no hand-edited JSON.
- [ ] Ship `.mcpb` per platform. Note `dart compile exe` **cannot cross-compile** except
      to Linux — macOS binaries require a macOS build machine, so this is a 2–4 leg CI
      matrix (macos-arm64, macos-x64 if still supported, plus Linux/Windows if targeted).
- [ ] Optionally list on [registry.modelcontextprotocol.io](https://registry.modelcontextprotocol.io)
- [ ] Document the manual config fallback:

```json
{
  "mcpServers": {
    "sats-stack": {
      "type": "stdio",
      "command": "/Applications/Sats Stack.app/Contents/MacOS/satsstack-mcp",
      "args": ["--allow-writes"]
    }
  }
}
```

Claude Desktop: `~/Library/Application Support/Claude/claude_desktop_config.json`.
Claude Code: `claude mcp add`, or `.mcp.json` in a project (same `mcpServers` shape).
The `mcpServers` key is a de facto convention other agents follow too.

### Phase 6 — Bonus: rebuild the in-app AI on the same tool layer
The current in-app assistant stuffs a **static snapshot** into the system prompt —
[ollama_service.dart:266](../lib/core/services/ollama_service.dart) sends totals,
surplus, and top-3 categories, with no tool calling. It therefore *cannot* accurately
answer "how much did I spend on dining out last month" — it can only riff on a summary.

Once the typed tool layer exists in `sats_stack_data`, the in-app AI can call the same
functions in-process. Same work, second payoff, and it fixes a real accuracy problem in
a feature that already ships.

---

## 6. Open questions

1. **Full Disk Access** — does a fresh unsigned binary reading
   `~/Library/Containers/com.satsstack.satsStack/...` trigger a TCC prompt on current
   macOS? Materially changes install UX. *(Phase 1)*
2. **Signing/notarization** — a binary shipped inside the `.app` bundle inherits its
   signature; a standalone `.mcpb` needs its own notarization. Which distribution?
3. **`dart_mcp` churn** — it self-describes as experimental. Acceptable for a local
   stdio server, but pin the version and expect breakage.
4. **Write scope** — should v1 ship writes at all, or read-only until the read path is
   proven? Read-only is the lower-risk, higher-value half of the original ask.
5. **Multi-currency** — `add_transaction` with a fiat amount needs a BTC price at the
   transaction date. Reuse `getHistoricalPrice()`, but decide the behavior when the
   date predates the `BtcPriceHistory` cache.

---

## 7. Sources

- MCP `2026-07-28` spec + changelog — modelcontextprotocol.io/specification/2026-07-28
- MCP release announcement — blog.modelcontextprotocol.io/posts/2026-07-28
- SDK 2.x betas — blog.modelcontextprotocol.io/posts/sdk-betas-2026-07-28
- MCPB bundles — blog.modelcontextprotocol.io/posts/2025-11-20-adopting-mcpb, github.com/modelcontextprotocol/mcpb
- MCP registry — registry.modelcontextprotocol.io
- Agent Skills spec — agentskills.io/specification
- Claude Code skills — code.claude.com/docs/en/skills.md
- Skills overview / best practices — platform.claude.com/docs/en/agents-and-tools/agent-skills/
- Claude Code MCP setup — code.claude.com/docs/en/mcp-quickstart
- `dart_mcp` — pub.dev/packages/dart_mcp · `mcp_dart` — pub.dev/packages/mcp_dart
- `dart compile` limits — dart.dev/tools/dart-compile
