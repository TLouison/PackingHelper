# PackingHelper Roadmap

Open work carried over from the 2026-10-21 codebase audit (completed items removed).
Each chunk is sized for one PR. Line numbers drift — re-verify before starting an item.

Paths are relative to `PackingHelper/`. `PLDE/` = `Views/Model Views/PackingList/PackingListDetailEdit/`.

**Suggested order:** 1 → 2 → 3 → 8 → 4 → 5 → 7 → 6 → 9 → 10 + 11 → 12. Update docs alongside whichever chunk invalidates them.

---

## 1. Small bug fixes

- **Packers can't be assigned on a new trip.** `TripDetailPackingView` passes `trip.packers` (derived from users already on items) → nil on new trips → no picker. `Trip.packers` is `Array(Set(...))`, so order is unstable. Fix: pass all users from a sorted `@Query`; keep `trip.packers` for display, sorted by `created`. Same in `AIAssistantSheet`.
- **Template apply footer copy** still says "packer who created it" (`PackingListApplyDefaultView.swift`); stale comment in `TripEditView`.
- **Weather cache** — minimal fix landed; full fix is 6.2.

## 2. Dead code & hygiene

The app sources are a synced folder, so deleting a file on disk removes it from the target.

**Unused files:** `Users/UserListView.swift` + `UserListRowView.swift`; `Users/Components/UserPickerBaseView.swift`; `Users/UserView.swift`; `TripDetail/Sheets/TripDetailSheet.swift`, `TripSettingsSheet.swift`; `TripDetailPackingGaugeRowView.swift`; `Models/Preferences.swift`; `Preview Content/PreviewContainer.swift`; `Utilities/CacheUtilities.swift` (unless reused for 6.2); `/AIPrompts.xcconfig`.
- **Decision:** `SubscriptionAwareButton` hardcodes `canPerformAction = true` — wire to `PurchaseManager` or replace with `Button`.
- **Decision:** `User.defaultLocation` (home base, Settings → Your Profile) has no consumer since `TripEditView` stopped setting `origin`. Bring origin back (prefilled from it, asked on the first trip) or drop both in the §12 schema change.

**Dead code inside live files** (verify no callers first):
- `Trip.swift`: many unused helpers (`incompleteItemsCount`, `defaultTaskList`, `getLists(for:…)` variants, `create_or_update`, `delete`, `hasMultiplePackers`, `sampleTrip` — a global model that schedules real notifications; switch previews to `.sampleData`).
- `PackingList.swift`: `filtered(user:)`, `containsMultiplePackers`, sample lists, legacy `createDefaultList`, `removeItem(at:)`.
- `TripLocation.swift`: `update(...)` ×2, `from(data:)` (force unwrap), `coordinates`, `Codable` + `DefaultLocationInformation`.
- `TripDetailView`, `TripListRowView`/`TripListScrollView`, Shop CTA (copy promises "unlimited trips, templates, share lists"; Plus actually gives AI + Unsplash search/Load More), `UserPickerView`, `PackingEngineCore` result types, `WeatherUtilities.getCurrentTemperatureString`, commented-out previews.
- Check `ProductSuggestionModel.mlproj` "… 1 copy" files.

## 3. Data integrity ⚠️ some delete-rule changes

- **3.2 (rest):** `User.lists` is still `.cascade` — deleting a user can delete whole trip sections. Change to `.nullify` (or clear legacy `PackingList.user`). Developer reset should delete trips + templates and match its copy.
- **3.3 Orphaned `TripLocation` rows** — new row per destination pick, never deleted; trip delete leaves them. Clean up in save/delete or `.cascade` on `origin`/`destination`.
- **3.4 Template copy bugs:** `copyItem.list = item.list` wires copies to the source list; `Item.copy` keeps `isPacked` on apply.
- **3.5 One delete function per entity** (`Trip.delete(in:)` cancels notification, cleans locations; same for list/user).

## 4. Dates, status & notifications

- **4.1** Trip dates keep creation time-of-day; `.departing`/`.returning` use `Date.now == startDate` (unreachable). Normalize to start of day on save; use `Calendar.isDateInToday`. `TripListView` predicates capture `now` once — refresh on scene active.
- **4.2** Day-of notification (behind `showingNotifications`): scheduled in `Trip.init` before lists exist, never rescheduled/cancelled, random ID, hardcoded 8 AM. Build a `TripNotificationScheduler` with stable id `dayOf-<uuid>`, awaited auth, `notificationTime` setting (re-add its Settings picker to the Trips section), `rescheduleAll` on foreground.
- **4.4** "Duration" is nights in some places, days in others; `countAsDays` gives 0 on day trips. Define `nights` and `days = nights + 1`.
- **4.5** Forecast labels off by a day for far time zones; window can skip day one / overrun trip end; weather doesn't refresh after editing destination/dates. Store `TripLocation.timeZoneIdentifier`, `.task(id:)`.
- **4.6** Forecast hardcodes °F; chip uses locale.

## 5. Item creation, ordering & counts

- **5.1** Drag-reorder lands in the wrong spot when visible ≠ stored items (packer filter, pending checks). Position by neighbor ("insert before X"), renumber all items.
- **5.2** Main add flow never ML-categorizes (`Item.create` has no callers). One `Item.create(...)` used by the container and AI paths.
- **5.3** Template-applied lists lose `isDayOf`/`type`; list menus unsorted.
- **5.4** Progress counts disagree (rows vs `count`, ignore user filter).
- **5.5** Template "Last Updated" never changes on edit/delete.
- **5.6** Section `.draggable` active outside reorder mode.

## 6. Weather & concurrency

- **6.1** Weather methods on `TripLocation` and `AITripContextBuilder.build` read model state off-main → `@MainActor`, snapshot inputs.
- **6.2** Move weather caching into a `WeatherProvider` actor (cache successes only, one `WeatherService`); drop `@Transient weather` / `weatherLastFetched`.
- **6.3** `FeatureFlags` singleton read from model code → `@MainActor` or read UserDefaults directly.
- **6.4** `PackingHelperApp.purchaseManager` has no wrapper → `@State`.
- **6.5** Verify with `-com.apple.CoreData.ConcurrencyDebug 1`; then strict concurrency / Swift 6 (currently Swift 5.0).
- **6.6** Replace `DispatchQueue.main.asyncAfter` timing hacks with cancellable `Task.sleep` / scroll APIs.
- **6.7** Notification `add` ignores errors.

## 7. AI assistant & Plus

- **7.1** AI sheet captures `targetUser` once; packer changes ignored; no dedupe against existing trip items.
- **7.3 (rest)** Map Worker 400 to a distinct error.
- **7.4** Paying users can see the paywall when RevenueCat lookup fails; Unsplash can loop on it. Add `reconcileWorkerRejection()` → paywall only on `.lapsed`; Worker returns 503 when RC is unreachable.
- **7.5 (rest)** Loading hint while context builds.
- **7.6** Failed message can't be retried; next send has two user turns.
- **7.7** One unknown `category` fails the whole reply — lenient decoding.
- **7.8** Plus state under two names (`isPlusActive`, `hasUnlockedPlus`).
- **7.9** Initial `customerInfo()` can overwrite a fresher refresh.

## 8. Security & release

- **8.3 (rest)** DEBUG-only Worker URL override field in Developer Menu.
- **8.4** Rotate `CLOUDFLARE_AI_TOKEN` if any build containing it (commit `944736d`) was distributed.

## 9. iOS 26 cleanup

Drop dead `#available(iOS 26…)` else-branches (`User.swift`, `ViewModifierUtilities.swift`, `WeatherChip.swift`), inline `glassEffectIfAvailable()`, remove `@available(iOS 18…)` annotations.

## 10. Refactors

- **10.1 `PackingEditor`** — `@MainActor @Observable` class in the environment owning add/edit/pending-pack state and actions; collapses `FocusPackingInput` / `PackingAddFlow` and the add/edit logic in the container. Folds in 5.1, 5.2, 6.6, 11.3.
- **10.2** Split `PackingListContainerView` (~800 lines); one `enum ActiveSheet` + `.sheet(item:)`.
- **10.3** `PersistentTextField` calls `becomeFirstResponder` on every update while focused; react to focus transitions only.
- **10.4** Model API consolidation: one create / copy / save strategy; `Trip.packingProgress` one-pass.
- **10.5** Shared `TripBackgroundView` (list row + hero) and `Trip.statusDateText`.
- **10.6** Shared modifiers: `.groupedCard`, `.deleteConfirmation`, `.editSheetToolbar`, `InfoRow`; move `FlowLayout` out of AI.
- **10.7** `WorkerClient` shared by AI + Unsplash services.
- **10.9** Misc: `UserPickerView` duplication, `UserColorPicker` `.opacity(.infinity)`, inconsistent default hex, `StorageKey` enum, `TripEditView` swipe-dismiss discards changes, `try?` swallowing in cover photo code, AI task routing relies on legacy `PackingList.type`.

## 11. Performance

- **11.1** Every trip card is a live `MKMapView` → `MKMapSnapshotter` images, cached.
- **11.2** Repeated `sortedLists` / item walks per body in sectioned view and summary bar.
- **11.3** Every check-off re-renders the whole sectioned view (fixed by 10.1).
- **11.4** Non-lazy `VStack` for all rows → `LazyVStack`.
- **11.5** `Trip.allItems` re-flattened per access.
- **11.7** UUID fetches without `fetchLimit = 1` (`ReorderableItemsSection`).
- **11.8** `TripEditView` copies cover photo bytes in init; `CoverPhotoImageView` reads `imageData` on main.
- **11.9 / 11.10 (optional)** BlurHash cosine tables; store enum `type` fields as raw `String` for `#Predicate`.

## 12. Schema cleanup ⚠️ one change, do last

- Remove legacy `PackingList.type`, `.user`, `.isDayOf` (`countAsDays`?), `Item.unifiedSortOrder`, `User.lists`.
- `Item.category` written, never read. `Trip.dayOfNotificationUUID` written, never read.
- **Decision:** no UI creates task items, day-of items, or `countAsDays` templates (only AI makes tasks). Build UI or remove those paths.

## Docs

- README: setup (`Config.xcconfig.example` → `Config.xcconfig`, WeatherKit entitlement, `scripts/run-on-device.sh`).
- SPEC.md §7: stale paths (`CoverPhoto/` folder; library cache key is `uuid`).
