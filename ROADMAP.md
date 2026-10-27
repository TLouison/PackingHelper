# PackingHelper Roadmap

Open work carried over from the 2026-10-21 codebase audit, re-verified against the code on 2026-10-27 (`d907169`); completed items removed.
Each chunk is sized for one PR. Line numbers drift — re-verify before starting an item.

Paths are relative to `PackingHelper/`. `PLDE/` = `Views/Model Views/PackingList/PackingListDetailEdit/`.

**Tags:**
- **[Behavior]** — changes what the user sees or what happens to data; needs testing in the app.
- **[No change]** — cleanup, refactor, or performance work; the app should behave exactly the same. A build plus a quick smoke test is enough.
- **[Ops]** — not a code change.

Keep [Behavior] and [No change] work in separate PRs where possible, so a refactor PR never hides a behavior change.

**Suggested order:** 1 → 2 → 3 → 8 → 4 → 5 → 7 → 6 → 9 → 10 + 11 → 12. Update docs alongside whichever chunk invalidates them.

---

## 1. Small bug fixes

- **[Behavior] Packers can't be assigned on a new trip.** `TripDetailPackingView` (~line 64) passes `trip.packers` (derived from users already on items) → nil on new trips → no picker. `Trip.packers` is `Array(Set(...))`, so order is unstable. Fix: pass all users from a sorted `@Query`; keep `trip.packers` for display, sorted by `created`. Same in `AIAssistantSheet`.
- **Weather cache** — minimal fix landed; full fix is 6.2.

## 2. Dead code & hygiene

The app sources are a synced folder, so deleting a file on disk removes it from the target.

- **[No change] Unused files** (no references outside themselves or their previews): `Users/UserListView.swift` + `Users/Components/UserList/UserListRowView.swift`; `Users/Components/UserPickerBaseView.swift`; `Users/UserView.swift` (already fully commented out); `TripDetail/Sheets/TripDetailSheet.swift`, `TripSettingsSheet.swift`; `TripDetailHelpers/TripDetailPackingGaugeRowView.swift`; `Models/Preferences.swift` (also the commented `Preferences.self` in `PackingHelperApp.swift`); `Preview Content/PreviewContainer.swift`; `Utilities/CacheUtilities.swift` (`TransientCache`, unused — unless reused for 6.2).
- **[No change] Dead code inside live files** (verified no callers on 2026-10-27):
  - `Trip.swift`: `defaultTaskList`, `create_or_update`, `delete` (or keep and use it for 3.5), `hasMultiplePackers`, `maxFreeTrips` + its commented/disabled CTA code (`TripListScrollView`, `TripListRowView`, `TripListView`), `sampleTrip` (only used by the dead `TripDetailSheet`/`TripSettingsSheet` previews; it's a global model that schedules real notifications). `incompleteItemsCount` is only used by the notification body (4.2 replaces it).
  - `PackingList.swift`: `filtered(user:)`, `containsMultiplePackers`, `removeItem(at:)`, `samplePackingList()` / `sampleDefaultList()`, `icon` (keep `iconImage`, it's used).
  - `TripLocation.swift`: `update(...)` ×2, `from(data:)` (force unwrap), `Codable` conformance + `DefaultLocationInformation`.
  - `WeatherUtilities.getCurrentTemperatureString`; `PackingEngineCore` result types (`PackingRecommendationStatus`, `PackingRecommendationResult` — check); commented-out code and previews (e.g. `TripDetailInfoView`, `SubscriptionAwareButton`).
  - `ProductSuggestionModel.mlproj/`: "ProductSuggestionModel 1 copy.json" / ".mlmodel".
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
- **5.2** Main add flow never ML-categorizes (`Item.create` has no callers). One `Item.create(...)` used by the container and AI paths.
- **5.4** Progress counts disagree: `totalItemsCount` / `packedItemsCount` count rows, not `count`, and ignore the packer filter.
- **5.5** Template "Last Updated" (`PackingList.lastUpdatedDate`, newest item `created`) never changes on edit/delete.

## 6. Weather & concurrency

- **6.1 [No change]** Weather methods on `TripLocation` and `AITripContextBuilder.build` read model state off-main → `@MainActor`, snapshot inputs.
- **6.2 [No change]** Move weather caching into a `WeatherProvider` actor (cache successes only, one `WeatherService`); drop `@Transient weather` / `weatherTripDates` / `weatherLastFetched` (dropping the stored `weatherLastFetched` is a schema change — fine pre-release, or fold into §12).
- **6.3 [No change]** `FeatureFlags.shared` read from model code (`Trip.init`, `createDayOfPackingNotification`, `NotificationUtilities`) → `@MainActor` or read UserDefaults directly.
- **6.4 [No change]** `PackingHelperApp.purchaseManager` has no wrapper → `@State`.
- **6.5 [No change]** Verify with `-com.apple.CoreData.ConcurrencyDebug 1`; then strict concurrency / Swift 6 (project is still `SWIFT_VERSION = 5.0`).
- **6.6 [No change, timing-sensitive]** Replace the 8 `DispatchQueue.main.asyncAfter` timing hacks (container, Focus, `ItemRowViews`, `TripListRowView`, `TripDetailHeroView`) with cancellable `Task.sleep` / scroll APIs. Should look identical; test keyboard and scroll behavior.
- **6.7 [No change]** Notification `add` ignores errors — log them.

## 7. AI assistant & Plus

- **7.1 [Behavior]** AI sheet passes `targetUser` once to `prepare` in `.task`; later packer changes are ignored. Existing item names are already sent to the model, but adding a suggestion doesn't skip items already on the trip.
- **7.3 (rest) [Behavior]** Map Worker 400 to a distinct error (currently falls into `.server(400)`).
- **7.4 [Behavior]** Paying users can see the paywall when the RevenueCat lookup fails (401 → `subscriptionLapsed` immediately); Unsplash can loop on it. Add `reconcileWorkerRejection()` → paywall only on `.lapsed`; Worker returns 503 when RC is unreachable.
- **7.5 (rest) [Behavior]** Loading hint while context builds.
- **7.6 [Behavior]** Failed message can't be retried and stays in `entries`, so the next send has two user turns.
- **7.7 [Behavior]** One unknown `category` fails the whole reply (`PackingRecommendationCategory` decoded strictly) — lenient decoding.
- **7.8 [No change]** Plus state under two names (`isPlusActive`, `hasUnlockedPlus`, both still used).
- **7.9 [Behavior]** The initial `customerInfo()` in `PurchaseManager.start()` can overwrite a fresher stream/refresh result.

## 8. Security & release

- **8.3 (rest) [Behavior, DEBUG only]** Worker URL override field in the Developer Menu. `AIAssistantService` already reads `debug_workerURLOverride`; only the UI is missing.
- **8.4 [Ops]** Rotate `CLOUDFLARE_AI_TOKEN` if any build containing it (commit `944736d`) was distributed.

## 9. iOS 26 cleanup — [No change]

Drop dead `#available(iOS 26…)` else-branches (`User.swift`, `ViewModifierUtilities.swift`), inline `glassEffectIfAvailable()`, remove the ~20 `@available(iOS 18…)` annotations on previews. Leave `VerticalToolbarReader`'s `iOS 27.1` check.

## 10. Refactors — [No change] unless noted

- **10.1 `PackingEditor`** — `@MainActor @Observable` class in the environment owning add/edit/pending-pack state and actions; collapses `FocusPackingInput` / `PackingAddFlow` and the add/edit logic in the container. Folds in 5.1, 5.2, 6.6, 11.3 — those parts are [Behavior]; land the pure refactor first or keep them as separate commits.
- **10.2** Split `PackingListContainerView` (~790 lines); one `enum ActiveSheet` + `.sheet(item:)` (currently 7 `.sheet` calls).
- **10.4** Model API consolidation: one create / copy / save strategy; `Trip.packingProgress` one-pass.
- **10.5** Shared `TripBackgroundView` (list row + hero) and `Trip.statusDateText`.
- **10.6** Shared modifiers: `.groupedCard`, `.deleteConfirmation`, `.editSheetToolbar`, `InfoRow`; move `FlowLayout` out of `AI/AISuggestedItemList.swift`.
- **10.7** `WorkerClient` shared by AI + Unsplash services.
- **10.9** Misc:
  - [No change] `UserPickerView` duplication, `UserColorPicker` `.opacity(.infinity)` (→ drop it), `StorageKey` enum, `try?` swallowing in cover photo code (log errors).
  - [Behavior] Inconsistent default user color (`User.colorHex` teal `008080`, `setUserColor` fallback `007AFF`, `WelcomeView` `#007AFF` with a `#`); `TripEditView` swipe-dismiss discards changes.

## 11. Performance — [No change] (should look and behave the same)

- **11.1** Every trip card is a live `Map` (`TripListRowView`) → `MKMapSnapshotter` images, cached. Check the cards look the same.
- **11.2 / 11.3** Written against the old sectioned view, which Focus replaced. Re-check `FocusPackingView`: repeated `sortedLists` / item walks per body, and whether one check-off re-renders every page (10.1 would fix the latter).
- **11.4** Focus's All page uses a `LazyVStack`; check the per-list pages and the template editor.
- **11.5** `Trip.allItems` re-flattened per access.
- **11.7** UUID fetch without `fetchLimit = 1` (`ReorderableItemsSection` drop handler).
- **11.8** `TripEditView` copies cover photo bytes in init (`CoverPhotoDraft(_:)` copies `imageData`); `CoverPhotoImageView` reads `imageData` on main.
- **11.9 (optional)** BlurHash cosine tables.

## 12. Schema cleanup ⚠️ one change, do last — [Behavior] (data reset)

- Remove legacy `PackingList.user` (trip lists only), `countAsDays`?, `Item.unifiedSortOrder`, `User.lists`.
- `Trip.dayOfNotificationUUID` is written, never read (4.2's stable id makes it unnecessary).
- No UI creates `countAsDays` templates. Build UI ([Behavior]) or remove.
- `User.defaultLocation` if §2's decision is to drop it; `TripLocation.weatherLastFetched` if 6.2 didn't already.
- (Optional, was 11.10) Store enum `type` fields as raw `String` for `#Predicate`.

## Docs — [No change]

- README is three lines: add setup (`Config.xcconfig.example` → `Config.xcconfig`, WeatherKit entitlement, `scripts/run-on-device.sh`).
- SPEC.md: stale paths and line numbers throughout — e.g. the file table names `SectionedPackingListView.swift` and `Shared/PackingListSectionHeader.swift` (both gone) and cites `TripEditView.swift:419` / `PackingListApplyDefaultView.swift:176`; library cover photo cache key is `uuid`.
