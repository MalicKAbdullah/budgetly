# Performance: fingerprint to home

How Budgetly gets from the biometric prompt to a filled home screen, and the
rules that keep it fast with a large vault.

## The unlock path

1. `main()` reads secure storage once (`CachedSecureStorage`) and draws the
   first frame already locked.
2. core_lock's `AppLockGate` keeps the router mounted under `Offstage`, and
   `LockScreen` raises the biometric prompt from its first post-frame
   callback. The home screen is therefore built **while the prompt is up**,
   which starts the vault load.
3. `AppDataNotifier.build` reads the vault file and the data key (from
   memory), then decrypts and parses the dataset **on a background isolate**
   (`BudgetlyStore.load` → `Isolate.run`). The UI isolate stays free to answer
   the platform's biometric reply.
4. When the data arrives (normally still under the prompt), the dashboard
   builds once. `dashboardSummaryProvider` computes every figure on the home
   screen in one pass and keeps it; the home-screen widget snapshot reads the
   same summary.
5. The fingerprint matches, the lock cover goes away, and the home is painted
   from the figures already computed. Rebuilds after that reuse the summary
   until the data, the period filter or the calendar day changes.

## Where the work runs

| Work | Runs on | Cost, 5,000 transactions |
| --- | --- | --- |
| AES-GCM decrypt + `jsonDecode` + `AppData.fromJson` | background isolate | ~86 ms wall, ~2 ms on the UI isolate |
| `toJson` + `jsonEncode` + encrypt, on every save | background isolate | ~78 ms wall, ~2 ms on the UI isolate |
| `PeopleMigration.run` on load | UI isolate | 0.4 ms (one pass; no copy when nothing changes) |
| `RecurringMaterializer.run` on load | UI isolate | proportional to templates, not transactions |
| `DashboardSummary.compute` | UI isolate, once per data / filter / day | 1.5–2 ms |
| `WidgetSnapshot.fromSummary` | UI isolate | 0.1 ms |

Saves encrypt concurrently but reach the file in call order, so an older
snapshot never overwrites a newer one.

`DashboardSummary` is pure: one pass over the transactions builds per-day,
per-month and per-year own-share spend keyed by `yyyymmdd` integers
(`DashboardFlow.dayKey`), the month's per-category spend, the filter window's
totals, category split and account flows, every account's balance, the four
latest transactions and today's count. `PeopleLedger.positions` runs once and
feeds both the people section and the savings position. Every value equals the
corresponding `DashboardFlow` / `Budgets` / `Balances` / `PeopleLedger` /
`Savings` function; `test/dashboard_summary_test.dart` checks that on random
5,000-transaction vaults across presets, custom, multi-year and reversed
ranges. Among transactions with the same timestamp, "Recent" lists the one
recorded later first.

`DashboardFlow.inRange` compares day keys rather than constructing three
`DateTime`s per call, which also speeds up the activity list filter and the
statement export.

## The activity list

`activityListProvider` holds the filtered transactions grouped into days with
each day's and the window's totals (`ActivityList.of`), keyed by the filter
set and window and recomputed only when those or the data snapshot change —
typing in the search box recomputes it, scrolling and rebuilds do not.

Each day is a `SliverMainAxisGroup` of a pinned `TxnDayHeader` and a
`TxnDayCard`: a `SliverList.builder` of rows inside two `DecoratedSliver`s
that draw the grouped-card fill and border exactly as `RowGroup` does (the
border clipped to the rounded outline, as a `Material` clips it). Every row
sits on its own transparent `Material`, so its ink shows above the fill, and
the first and last rows clip that ink to the rounded corners. Rows are built
as they scroll into view. Pinned day headers need one sliver group per day,
so every day's header is still built, and each off-screen day builds its
first row, which `SliverList` uses to estimate the day's height.

## Measurements

`flutter test test/perf` (JIT), Apple M-series, median of repeated runs. Vault:
5,000 transactions over two years, 6 accounts, 15 categories, 10 people,
splits both ways, settlements (some legacy), transfers — 1.06 MB encrypted.
"Longest UI stall" is the longest time the calling isolate's event loop could
not run during the operation, i.e. how long a frame or the biometric reply
would have waited.

### Vault load and save

| | UI isolate (main) | Background isolate (now) |
| --- | --- | --- |
| Decode: wall time | 85 ms | 87 ms |
| Decode: longest UI stall | 86 ms | 1.9 ms |
| Encode: wall time | 77 ms | 78 ms |
| Encode: longest UI stall | 79 ms | 1.5 ms |

### Dashboard figures

| | Per-widget roll-ups, every build (main) | `DashboardSummary` (now) |
| --- | --- | --- |
| "This month" filter | 106 ms per build | 1.6 ms per data / filter / day change |
| "All time" filter | 76 ms per build | 2.0 ms per data / filter / day change |
| Home-screen widget snapshot | 2.3 ms per data change | 0.1 ms (reads the summary) |
| `spentInRange`, all time | 6.4 ms | 0.3 ms |

The per-widget column is every call one dashboard build made when each card
computed its own figures (`test/perf/dashboard_benchmark_test.dart` keeps that
baseline, with the allocating range check, in `test/perf/naive_flow.dart`).

A mid-range Android phone is roughly 4–5× slower than these figures and AOT
roughly 1.5–2× faster than JIT, so on a phone: the vault decode (~0.3–0.4 s)
overlaps the prompt without stalling it, and the home's first unlocked frame
does no dataset work; the summary costs ~5–10 ms once when the data arrives.

### Activity list ("All time", 5,000 transactions over 730 days)

`test/perf/activity_benchmark_test.dart`, a 390×844 view in a widget test.
The first frame covers build, layout and paint.

| | One `RowGroup` per day (main) | `TxnDayCard` (now) |
| --- | --- | --- |
| Rows built on the first frame | 5,000 | 742 (12 on screen + 1 per other day) |
| First frame | 2,800 ms | 600 ms |
| Filter + group + per-day totals | 3.9 ms on every build | 2.0 ms per data / filter change |

## Timing logs

Debug and profile builds log to `developer.log` (watch with
`flutter run --profile`):

- `budgetly.startup` — secure storage ready, first frame.
- `budgetly.perf` — `vault decrypt + parse`, `vault serialize + encrypt`,
  `dashboard summary`, each with its duration and size.

## Rules

- Whole-dataset CPU work (crypto, JSON, parsing) runs through `VaultWorker`
  (`Isolate.run`), never on the UI isolate. A closure sent to an isolate is
  built in a scope that holds only sendable values.
- Long lists build their rows lazily (`SliverList.builder`); a grouped card
  is drawn with `DecoratedSliver`s around the lazy rows, not by a widget
  that holds every row.
- Widgets never roll up transactions in `build`. Derived figures come from a
  provider that recomputes only when its inputs change.
- New dashboard figures go into `DashboardSummary`'s single pass, with an
  equivalence test against the plain roll-up.
