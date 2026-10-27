# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PackingHelper is an unreleased iOS travel preparation app built with SwiftUI and SwiftData. It helps users organize packing lists and tasks before trips, track items across multiple travelers, and reduce pre-trip anxiety.

**Tech Stack:** SwiftUI (iOS 26+), SwiftData, RevenueCat (subscriptions), WeatherKit, MapKit, CoreML

## Commands

Do not run commands that build the app, launch or control the iOS Simulator, or run tests (e.g. `xcodebuild`, `xcrun simctl`, `swift test`). The user will handle those; just tell them what to run and when.
Other commands (e.g. `git`, file inspection, search) are fine to run.

## Architecture

### Data Model (SwiftData)

The app uses SwiftData with seven models. All models have a `uuid`; use it (not `persistentModelID.hashValue`, which is reseeded every launch) for any key that must survive relaunch.

**Trip** (root entity)
- Properties: `name`, `startDate`, `endDate`, `types` (plane/car/train/boat/ferry; multi-select, `primaryType` is the icon), `accomodations` (multi-select)
- Has-many: `lists` (PackingList, cascade delete)
- Has-one: `origin`, `destination` (TripLocation), `coverPhoto` (TripCoverPhoto, cascade delete)
- Extensions provide rich computed properties: `.status`, `.packers`, `.totalItems`, `.packedItems`
- `.packers` is derived from users already assigned to items, so it is empty on a new trip — query all users when you need a packer picker
- Status calculation based on dates: `.upcoming`, `.departing`, `.active`, `.returning`, `.complete`

**PackingList** (a section of a trip, or a template)
- User-facing copy calls a trip's sections **lists** ("New List", "Edit List"), never "section" or "bag"; packed items sit under **Packed**. Code still says section in names and comments
- Properties: `name`, `template`, `isDefault`, `sortOrder`, `countAsDays`, `kind` (`ListKind`: packing / tasks, stored as `kindRawValue`), `isDayOf`; Default is always everyday packing
- Kinds: task lists check items off as "Done" instead of "Packed" (`ListKind.checkedWord`). Either kind can be day-of (for the day you leave): day-of lists stay at the end of a trip's lists when new lists are added (`Trip.addList`) and feed trip detail's "left for today" line. Task and day-of lists show a glyph (`ListKind.glyph(isDayOf:)`: checklist, DayOfPacking, DayOfTask) before the list name via `ListNameLabel` / `ListMenuLabel` (`Views/Model Views/PackingList/ListNameLabel.swift`; chips, headers, menus, not the big page title); everyday packing lists show none. Every kind counts toward packed progress. Items have no kind of their own
- Belongs-to: `trip` (Trip); `user` (User) — owner for templates; legacy on trip lists
- Has-many: `items` (Item, cascade delete)
- Self-referencing: `appliedFromTemplate` / `appliedToLists` (nullify) for the template system. Applying a template snapshots its items; trip items can be saved back to templates, and lists made on a trip (not Default) can be saved as new templates (`saveAsNewTemplate`, which links the list) from the list menu or the end-of-trip review (`TemplateUpdateSheet`)

**Item**
- Properties: `name`, `count`, `isPacked`, `sortOrder`, `category`; legacy `unifiedSortOrder`
- Belongs-to: `list` (PackingList), `user` (User — the packer; packers are assigned per item, not per list)

**User**
- Properties: `name`, `created`, `profileImageData`, `colorHex`, `defaultLocation`
- Has-many: `items` (nullify); legacy `lists` (still `.cascade` — don't delete `user.lists` directly; use `User.delete`)
- Rich UI components: pill icon, profile view, initial icon with glass effect

**TripLocation**
- Properties: `name`, `latitude`, `longitude`
- Weather via `getTripWeather(for:)`, `getCurrentWeather(for:)`, `getWeatherForecast(for:)` (`@MainActor`; they hand plain values to `WeatherProvider`, which holds the cache)

**TripCoverPhoto** (in `CoverPhoto/`)
- Library or Unsplash image, `.externalStorage` bytes, BlurHash placeholder

**AIConversation**
- The saved AI assistant chat for one trip (`trip.aiConversation`) or template (`list.aiConversation`), cascade-deleted with it
- `entriesData` is the JSON-encoded `[AIAssistantViewModel.ChatEntry]`; cleared only by New Chat

Legacy fields above are slated for removal in one schema change (see ROADMAP.md §12); don't build new features on them.

### Key Patterns

**SwiftData Usage:**
- Use `@Query` with `FetchDescriptor` for reactive data fetching
- Filter with predicates: `#Predicate<Trip> { trip.endDate > now }`
- Models use static factory methods for CRUD (e.g., `User.create_or_update()`, `PackingList.save()`)
- Always specify cascade delete rules in `@Relationship` for parent-child relationships
- Access model context via `@Environment(\.modelContext)`

**View Architecture:**
- Component-based: break views into small, reusable pieces (row views, section headers, detail views)
- Container views handle state/logic, presentational views handle display
- Use `@State` for local UI state, `@Binding` for parent-child communication
- `@AppStorage` for user preferences (onboarding status, view modes); appearance follows the system by default
- Navigation uses `NavigationStack` with type-safe `NavigationPath`
- Don't nest `NavigationStack`s — pushed or sheet content that already has one must not be wrapped in another
- Empty-state actions use `EmptyStateButton` (`Views/General/`; extra-large glass, filled for the main action) with one or two short sentences of copy
- No emoji anywhere in the app (UI copy, labels, icons, sample data); use SF Symbols or the asset catalog's custom symbols. Emoji are fine in throwaway mockups only

**Focus State Management:**
- IMPORTANT: When using text fields with keyboards, manage focus at the parent level
- Item rows use `PersistentTextField` (UIKit-backed, keeps the keyboard up between rows) with a plain `Binding<Bool>` for focus, not `@FocusState`
- Always dismiss keyboard BEFORE animating view removal to prevent layout shifts
- Pattern: `isTextFieldFocused = false` → `withAnimation { ... remove view ... }`
- See PackingListContainerView, FocusPackingView for examples

**Extensions:**
- Models have extensive extensions grouping related functionality
- Computed properties for derived data (`.incompleteItems`, `.completeItems`, `.progress`)
- Sample data extensions for SwiftUI previews

### Navigation Hierarchy

```
ContentView (TabView)
├── TripListView (Trips tab; Settings opens as a sheet from its toolbar)
│   ├── TripListRowView
│   └── NavigationLink → TripDetailView
│       ├── TripDetailHeroView (cover photo or map + title; Edit lives in the nav toolbar)
│       ├── TripDetailPackingView (progress card; tap opens packing)
│       │   └── PackingListContainerView
│       │       └── FocusPackingView (chip rail + one page per section)
│       ├── TripDetailForecastView (weather)
│       └── TripDetailInfoView (details)
├── DefaultPackingListView (Templates tab; badge = past trips with template items to review)
│   └── PackingListContainerView (single template list)
└── UserGridView (Packers tab) [showingMultiplePackers flag]
```
Wide screens (iPad / unfolded) get split layouts for the trip list, templates, and an AI side panel in the packing view.

**Packing List Views (Critical Component):**
- `PackingListContainerView`: Hosts trip packing and single-template editing (the single-list path is template-only)
  - Provides shared toolbar, user selector, AI assistant sheet/panel; split across `PackingListContainerView+Toolbar/+Assistant/+Sheets.swift`. Every sheet goes through one `ActiveSheet` enum + `.sheet(item:)`
  - `PackingEditor` (`PackingListDetailEdit/PackingEditor.swift`, `@MainActor @Observable`, in the environment) owns the add-item state (inline row, target list, packer, count, focus as a plain `Bool`), Remove Items mode and its undo stack (`RemovedItem`s), template item editing, and the `PendingPackTracker`. The accessory bar above the keyboard is `Shared/NewItemAccessoryBar.swift`
- **Trip packing** uses `FocusPackingView` (`PackingListDetailEdit/Focus/`): a chip rail (tap to jump, hold + drag to reorder, + to create a section or apply a template) over a pager with an All page (every section under name headers), one page per section, and an "Add a List" page at the end; two pages side by side at ≥700pt width. Reads add / Remove Items / check-off state from the `PackingEditor` environment object and gets its list data and sheet callbacks through `FocusPackingInput` (`FocusPackingSupport.swift`, which also holds `PackingItemActions`, `RemovedItem`, `ItemDetailSheet`, `PackCheckbox`, `TileFlowLayout`). A section title's menu turns on Remove Items (minus buttons on every card, Undo + Done in the toolbar; `PackingEditor` keeps the undo stack as `RemovedItem`s)
- **Template editing** is `Shared/TemplateListEditorView.swift`, built on `Shared/ItemRowViews.swift` + `ReorderableItemsSection` (Reminders-style editing, drag to reorder):
  - `NewItemRow`: Inline add row; Return saves and keeps the row open, Return on empty or blur closes it (typed text is saved). Count lives in the accessory bar above the keyboard. `NewItemRow.scrollID(for:)` is also the scroll target for Focus's add row
  - `EditableItemRow`: Inline edit; commits on Return, blur, or disappear; backspace on empty name deletes the item
  - `UnifiedItemRow`: Display row with swipe-to-reveal delete and full-swipe delete
  - `AddItemTapZone`: Blank area at the end of the list; tap starts adding (or finishes adding)
- `Shared/PackingListSupportViews.swift`: `UserSelector`, `PendingPackTracker` (checked items stay in place ~1.5s, tap again to undo, before moving to Packed), `EmptyStateView`

### Special Components

**ML Integration (Packing Engine):**
- `PackingEngineCore.swift` uses CoreML's `ProductSuggestionModel`
- Categorizes items: Clothing, Electronics, Toiletries, Task, other
- API is `PackingEngine.interpretItem(itemName:)`, called only from `Item.create`, which currently has no callers — new items are not categorized yet (ROADMAP.md 5.2)

**Weather Integration:**
- `WeatherUtilities.swift` (`WeatherProvider` actor: one `WeatherService`, caches successful fetches only) + `TripLocation.swift` handle weather fetching
- Async/await pattern, 1-hour cache TTL keyed by place and trip dates
- Only fetches for trips within 5 days of start date
- Use `getTripWeather(for:)` / `getCurrentWeather(for:)` / `getWeatherForecast(for:)` on TripLocation

**Tips (TipKit):**
- Features are taught in context, not in onboarding. Tips live in `Views/General/PackingTips.swift`; `Tips.configure()` runs in `PackingHelperApp.init`
- The Focus packing tips (apply template, reorder sections) share one `TipGroup(.firstAvailable)` in `FocusPackingView`, so only one shows at a time; their rules read `@Parameter`s set from the view
- Developer Menu → "Reset Tips on Next Launch" (the datastore can only be reset before `configure`)

**Notifications:**
- `NotificationUtilities.swift` wraps UNNotification permission handling
- Day-of packing notification at 8 AM (hardcoded) on trip start date, gated by `showingNotifications`
- Check/request permissions before scheduling

**Purchase Management (Plus):**
- `PurchaseManager.swift` + RevenueCat SDK; read `purchaseManager.isPlusActive`
- Plus gates the AI packing assistant and Unsplash search + Load More (free users get one 25-photo page for their destination, no search bar). There is no trip limit
- New trips auto-pick a random Unsplash cover photo in `TripEditView` (Worker `/v1/photos/random`, not gated) unless Settings → Default Cover (`defaultTripCover`) is Map
- Settings opens with `PlusSettingsSection` (upsell card, or a status row → `PlusStatusView`, titled "Packing Helper Plus": plan state from `PurchaseManager.plusEntitlement`, Apple manage/refund sheets, Customer Center behind Contact Support); trip preferences go in its `TripSettingsSection`
- AI and Unsplash go through a Cloudflare Worker (`WORKER_URL`), which verifies the RevenueCat entitlement server-side

**AI Assistant:**
- `Views/AI/`, `ViewModels/AIAssistantViewModel.swift`, `Services/AIAssistantService.swift`, `Services/AITripContextBuilder.swift`
- Two modes: **trip** (fill gaps in the trip's lists, using destination, season, transport, stays, weather, and other packers' items) and **template** (a reusable starting point for a template list; opened from the template editor's toolbar, always as a sheet)
- The paywall opens over the chat (not instead of it), so buying lands the user back in the conversation; without Plus the composer becomes an Unlock bar
- The container keeps one `AIAssistantViewModel` per trip/template; it saves to `AIConversation`, so closing the assistant or leaving the screen keeps the chat until New Chat (the chat's ⋯ menu)
- Context is rebuilt on every send (weather once per session). Suggestions matching something the packer already has (`AITripContextBuilder.matchKey`: case, punctuation, simple plurals) are dropped client-side, and adding skips them
- The prompt lives in the Worker repo (`PackingHelperWorkers`, `src/prompt.ts`); request DTOs in `AIAssistantService.swift` must stay in sync with its README contract
- The Worker rejects history entries with empty content and conversations over 40 messages, so the client filters and trims history

### Feature Flags

Runtime `UserDefaults`-backed toggles on `FeatureFlags.shared` (`FeatureFlags.swift`), switched in the Developer Menu (Settings, DEBUG builds only):
- `showingMultiplePackers`, `showingNotifications`, `showingPackingEngine`, `showingProfilePictures`
- Flags are all off in Release builds (the menu is `#if DEBUG`), so a feature ships only once its flag is removed

### File Organization

```
PackingHelperApp.swift   # App entry + ModelContainer (repo root, outside the synced folder)
PackingHelper/           # Xcode synchronized folder — new files are added to the target automatically
├── Models/              # SwiftData models (+ Previews/SampleData.swift)
├── ViewModels/          # Lightweight view models (@Observable)
├── Services/            # Worker clients (AI) + shared WorkerClient (base URL, POST, status split)
├── CoverPhoto/          # TripCoverPhoto model, library/Unsplash pickers, loader, BlurHash
├── Views/
│   ├── Model Views/     # Entity-specific views (Trip/, PackingList/, DefaultPackingList/, Item/, Users/)
│   ├── AI/              # AI assistant sheet/panel
│   ├── Shop/            # Plus paywall/CTA
│   ├── Location/        # MKLocalSearchCompleter location search
│   ├── Weather/         # WeatherChip
│   ├── General/         # Shared UI components
│   ├── Onboarding/      # First-launch WelcomeView (creates the first packer; name optional, defaults to "Me")
│   └── Settings/        # App settings + Developer Menu
├── Utilities/           # Cross-cutting concerns (Color, Calendar, Style, Purchase, etc.)
└── PackingEngine/       # ML categorization
scripts/run-on-device.sh # Build, install, launch on a physical iPhone (works over Wi-Fi)
scripts/run-on-simulator.sh # Same for a Simulator; from Linux, rsyncs to the Mac (MAC_HOST) and builds there
```
Config values (`REVENUECAT_API_KEY`, `WORKER_URL`) come from the gitignored `Config.xcconfig` (template: `Config.xcconfig.example`) via Info.plist.

**Planned work:** see `ROADMAP.md` for the open bug/refactor backlog. Check it before touching an area — many known issues are already documented there.

**Naming Convention:**
- Views: `{Entity}{Action}View.swift` (e.g., TripEditView, PackingListDetailView)
- Row components: `{Entity}RowView.swift` or `{Purpose}Row.swift`
- Sheets/modals: Often in `/Sheets/` subdirectory

### Data Persistence Notes

**Migration:**
- The app is unreleased and has no data migrations; schema changes can assume device data is reset

**Preview Infrastructure:**
- `Models/Previews/SampleData.swift`: in-memory container with mock trips, lists, items, users
- Use `#Preview(traits: .sampleData)`.

**SwiftData Container Setup** (`User` is reached through relationships):
```swift
ModelContainer(for: Trip.self, TripLocation.self, PackingList.self, Item.self, TripCoverPhoto.self, AIConversation.self)
```

### Critical Dependencies

- **RevenueCat:** Subscription management (public SDK key from `Config.xcconfig`)
- **StoreKit:** Local testing via `PackingHelperPlus.storekit`
- **Cloudflare Worker:** AI assistant + Unsplash proxy (`WORKER_URL`)
- **WeatherKit:** Weather forecasts (requires entitlement)
- **CoreML:** ProductSuggestionModel must be included in project
- **MapKit:** Location display and geocoding

### Known Constraints

- App requires at least one User to display trips
- Weather data only fetched within 5 days of trip start
- iOS 26+ minimum deployment target — no `#available` fallbacks or `@available(iOS 18…)` annotations needed in new code
- iPhone is portrait-only; iPad supports all orientations
- Swift 5 language mode, no strict concurrency yet; `@Model` objects must be read on the main actor
- Some features currently disabled via feature flags (see FeatureFlags)
