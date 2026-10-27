# PackingHelper Roadmap

Open work carried over from the 2026-10-21 codebase audit, re-verified against the code on 2026-10-27 (`d907169`); completed items removed. The [No change] pass on 2026-10-27 (through `1f5eec6`) cleared §2's dead code, most of §6, 7.8, §9, §10, most of §11, and Docs.
Each chunk is sized for one PR. Line numbers drift — re-verify before starting an item.

Paths are relative to `PackingHelper/`. `PLDE/` = `Views/Model Views/PackingList/PackingListDetailEdit/`.

**Tags:**
- **[Behavior]** — changes what the user sees or what happens to data; needs testing in the app.
- **[No change]** — cleanup, refactor, or performance work; the app should behave exactly the same. A build plus a quick smoke test is enough.
- **[Ops]** — not a code change.

Keep [Behavior] and [No change] work in separate PRs where possible, so a refactor PR never hides a behavior change.

**Suggested order:** 1 → 2 → 3 → 8 → 4 → 5 → 7 → 6.5 → 10.4 + 11 → 12. Update docs alongside whichever chunk invalidates them.

---

## 1. Small bug fixes

- **[Behavior] Packers can't be assigned on a new trip.** `TripDetailPackingView` (~line 64) passes `trip.packers` (derived from users already on items) → nil on new trips → no picker. `Trip.packers` is `Array(Set(...))`, so order is unstable. Fix: pass all users from a sorted `@Query`; keep `trip.packers` for display, sorted by `created`. Same in `AIAssistantSheet`.

## 2. Dead code & hygiene

The app sources are a synced folder, so deleting a file on disk removes it from the target.

- **[No change] Leftovers** found during the 2026-10-27 dead-code pass: `plusSubscriptionWithText` (`Shop/PackingHelperPlusViews.swift`) has no callers; `Item.copyForTemplate` is only reached from the `template: true` branch of `PackingList._copy`, which nothing calls; `TripListScrollView.tripCard(_:index:)` ignores `index`. `ProductSuggestionModel.mlproj/Data Sources/itemClassifications.json` still names the deleted "1 copy" experiment — check Create ML still opens the project.
- **[Behavior] Shop CTA copy** (`Shop/PackingHelperPlusCTA.swift` ~130–138) promises "unlimited trips", "unlimited packing lists", "Share lists with travel companions". Plus actually gives AI + Unsplash search/Load More. Delete the view if nothing shows it, otherwise rewrite the copy.
- **Decision — `SubscriptionAwareButton`** hardcodes `canPerformAction = true` (used by `UserGridView`). Replacing it with a plain `Button` is [No change]; wiring it to `PurchaseManager` is [Behavior].
- **Decision — `User.defaultLocation`** (home base, Settings → Your Profile) is set in `UserEditView` but never read; new trips are created with `origin: nil`. Bringing origin back (prefilled from it, asked on the first trip) is [Behavior]; dropping both goes in the §12 schema change.

## 3. Data integrity ⚠️ delete-rule changes — all [Behavior]

- **3.2 (rest):** `User.lists` is still `.cascade`. `User.delete` clears it first, but anything calling `modelContext.delete(user)` directly can still delete whole trip lists and templates. Change to `.nullify` (or clear legacy `PackingList.user`). The Developer Menu's "Reset Onboarding State" does exactly that (`users.forEach { modelContext.delete($0) }`), and its copy says it wipes all trips, which it doesn't: make it delete trips + templates + users and match its copy (DEBUG only).
- **3.3 Orphaned `TripLocation` rows** — new row per destination pick, never deleted; trip delete leaves them. Clean up in save/delete or `.cascade` on `origin`/`destination`.
- **3.4 Template copy bugs** (`Item.swift`): `Item.copy` and `copyForTemplate` set `copyItem.list = item.list` (wires copies to the source list before they're appended to the new one); `Item.copy` keeps `isPacked` on apply, so packed template items arrive packed.
- **3.5 One delete function per entity.** Trips are deleted with a bare `modelContext.delete` in `TripEditView.deleteTrip()` and `TripListScrollView.deleteTrip()`. Route through `Trip.delete(in:)` that cancels the notification and cleans up locations; same for list/user.

## 4. Dates, status & notifications — all [Behavior]

- **4.1** Trip dates keep the creation time of day (`TripDateRangePicker` uses `keepingTime(of:)`); `.departing`/`.returning` use `Date.now == startDate` (unreachable). Normalize to start of day on save; use `Calendar.isDateInToday`. `TripListView` predicates capture `now` once (static) — refresh on scene active.
- **4.2** Day-of notification (behind `showingNotifications`): scheduled in `Trip.init` before lists exist, never rescheduled/cancelled, random ID, hardcoded 8 AM. Build a `TripNotificationScheduler` with stable id `dayOf-<uuid>`, awaited auth, `notificationTime` setting (re-add its Settings picker to the Trips section), `rescheduleAll` on foreground. The body should list what's in the trip's day-of lists (`trip.dayOfLists`) and skip trips with nothing left.
- **4.4** "Duration" is nights in some places, days in others: `TripDetailInfoView` shows `duration` (nights) as "days", the date picker says nights; `countAsDays` gives 0 on day trips. Define `nights` and `days = nights + 1`.
- **4.5** Forecast labels off by a day for far time zones; window can skip day one / overrun trip end. Store `TripLocation.timeZoneIdentifier`. (`TripDetailView` already uses `.task(id: WeatherRequest(trip:))`.)
- **4.6** Forecast defaults to °F (`TripDetailForecastView` `temperatureUnit = .fahrenheit`); the chip uses the locale.

## 5. Item creation, ordering & counts — all [Behavior]

- **5.1** Drag-reorder lands in the wrong spot when visible ≠ stored items (pending checks, packed items). `SortOrderManager.reorderItems` is still index-based. Position by neighbor ("insert before X"), renumber all items.
- **5.2** Main add flow never ML-categorizes (`Item.create` has no callers). One `Item.create(...)` used by `PackingEditor` and the AI path.
- **5.4** Progress counts disagree: `totalItemsCount` / `packedItemsCount` count rows, not `count`, and ignore the packer filter.
- **5.5** Template "Last Updated" (`PackingList.lastUpdatedDate`, newest item `created`) never changes on edit/delete.

## 6. Concurrency

- **6.5 [No change]** Weather, AI context, and notification-flag reads are now main-actor safe (`WeatherProvider` actor, `FeatureFlags.notificationsEnabled`). Verify with `-com.apple.CoreData.ConcurrencyDebug 1`; then strict concurrency / Swift 6 (project is still `SWIFT_VERSION = 5.0`).

## 7. AI assistant & Plus

- **7.3 (rest) [Behavior]** Map Worker 400 to a distinct error (currently falls into `.server(400)`).
- **7.4 [Behavior]** The assistant now refreshes CustomerInfo on a Worker 401 and only shows the paywall if RevenueCat agrees Plus is inactive. Still open: Unsplash can loop on the paywall the same way, and the Worker should return 503 (not 401) when RevenueCat is unreachable.
- **7.5 (rest) [Behavior]** Loading hint while context builds.
- **7.9 [Behavior]** The initial `customerInfo()` in `PurchaseManager.start()` can overwrite a fresher stream/refresh result.

## 8. Security & release

- **8.3 (rest) [Behavior, DEBUG only]** Worker URL override field in the Developer Menu. `WorkerConfig` (`Services/WorkerClient.swift`) already reads `StorageKey.workerURLOverride`; only the UI is missing.
- **8.4 [Ops]** Rotate `CLOUDFLARE_AI_TOKEN` if any build containing it (commit `944736d`) was distributed.

## 10. Refactors — [No change] unless noted

- **10.4 (rest)** Copy strategy: `Item.copy` / `copyForTemplate` / `PackingList._copy` are still separate (merging them touches 3.4's behavior; do it with 3.4). `Item.insertTemplateItem` now backs both save-to-template paths.
- **10.9 [Behavior]** Inconsistent default user color (`User.colorHex` teal `008080`, `setUserColor` fallback `007AFF`, `WelcomeView` `#007AFF` with a `#`); `TripEditView` swipe-dismiss discards changes.

## 11. Performance — [No change] (should look and behave the same)

- **11.3** Check whether one check-off still re-renders every Focus page now that pages observe `PackingEditor` (10.1).
- **11.4** Per-list pages and the template editor are still eager; making them lazy breaks `scrollTo` on `NewItemRow.scrollID`, add-row focus, and the drop zones. Only worth it with a different scroll-target approach.
- **11.9 (optional)** BlurHash cosine tables.

## 12. Schema cleanup ⚠️ one change, do last — [Behavior] (data reset)

- Remove legacy `PackingList.user` (trip lists only), `countAsDays`?, `Item.unifiedSortOrder`, `User.lists`.
- `Trip.dayOfNotificationUUID` is written, never read (4.2's stable id makes it unnecessary).
- No UI creates `countAsDays` templates. Build UI ([Behavior]) or remove.
- `User.defaultLocation` if §2's decision is to drop it.
- (Optional, was 11.10) Store enum `type` fields as raw `String` for `#Predicate`.
