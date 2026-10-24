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

The app uses SwiftData with six models. All models have a `uuid`; use it (not `persistentModelID.hashValue`, which is reseeded every launch) for any key that must survive relaunch.

**Trip** (root entity)
- Properties: `name`, `startDate`, `endDate`, `type` (plane/car/train/boat/ferry), `accomodation`
- Has-many: `lists` (PackingList, cascade delete)
- Has-one: `origin`, `destination` (TripLocation), `coverPhoto` (TripCoverPhoto, cascade delete)
- Extensions provide rich computed properties: `.status`, `.packers`, `.totalItems`, `.packedItems`
- `.packers` is derived from users already assigned to items, so it is empty on a new trip — query all users when you need a packer picker
- Status calculation based on dates: `.upcoming`, `.departing`, `.active`, `.returning`, `.complete`

**PackingList** (a section of a trip, or a template)
- Properties: `name`, `template`, `isDefault`, `sortOrder`, `countAsDays`; legacy `type`, `isDayOf`
- Belongs-to: `trip` (Trip); `user` (User) — owner for templates; legacy on trip lists
- Has-many: `items` (Item, cascade delete)
- Self-referencing: `appliedFromTemplate` / `appliedToLists` (nullify) for the template system. Applying a template snapshots its items; trip items can be saved back to templates

**Item**
- Properties: `name`, `count`, `isPacked`, `sortOrder`, `category`; legacy `type`, `isDayOf`, `unifiedSortOrder`
- Belongs-to: `list` (PackingList), `user` (User — the packer; packers are assigned per item, not per list)

**User**
- Properties: `name`, `created`, `profileImageData`, `colorHex`, `defaultLocation`
- Has-many: `items` (nullify); legacy `lists` (still `.cascade` — don't delete `user.lists` directly; use `User.delete`)
- Rich UI components: pill icon, profile view, initial icon with glass effect

**TripLocation**
- Properties: `name`, `latitude`, `longitude`
- Weather via `getTripWeather(for:)`, `getCurrentWeather(for:)`, `getWeatherForecast(for:)` with a 1-hour cache (`weather` is `@Transient`)

**TripCoverPhoto** (in `CoverPhoto/`)
- Library or Unsplash image, `.externalStorage` bytes, BlurHash placeholder

Legacy fields above are slated for removal in one schema change (see ROADMAP.md §12); don't build new features on them.

### Key Patterns

**SwiftData Usage:**
- Use `@Query` with `FetchDescriptor` for reactive data fetching
- Filter with predicates: `#Predicate<Trip> { trip.endDate > now }`
- Models use static factory methods for CRUD (e.g., `Trip.create_or_update()`, `PackingList.save()`)
- Always specify cascade delete rules in `@Relationship` for parent-child relationships
- Access model context via `@Environment(\.modelContext)`

**View Architecture:**
- Component-based: break views into small, reusable pieces (row views, section headers, detail views)
- Container views handle state/logic, presentational views handle display
- Use `@State` for local UI state, `@Binding` for parent-child communication
- `@AppStorage` for user preferences (onboarding status, view modes); appearance follows the system by default
- Navigation uses `NavigationStack` with type-safe `NavigationPath`
- Don't nest `NavigationStack`s — pushed or sheet content that already has one must not be wrapped in another

**Focus State Management:**
- IMPORTANT: When using text fields with keyboards, manage focus at the parent level
- Item rows use `PersistentTextField` (UIKit-backed, keeps the keyboard up between rows) with a plain `Binding<Bool>` for focus, not `@FocusState`
- Always dismiss keyboard BEFORE animating view removal to prevent layout shifts
- Pattern: `isTextFieldFocused = false` → `withAnimation { ... remove view ... }`
- See PackingListContainerView, SectionedPackingListView for examples

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
│       │       └── SectionedPackingListView (grouped by list)
│       ├── TripDetailForecastView (weather)
│       └── TripDetailInfoView (details)
├── DefaultPackingListView (Templates tab; badge = past trips with template items to review)
│   └── PackingListContainerView (single template list)
└── UserGridView (Packers tab) [showingMultiplePackers flag]
```
Wide screens (iPad / unfolded) get split layouts for the trip list, templates, and an AI side panel in the packing view.

**Packing List Views (Critical Component):**
- `PackingListContainerView`: Hosts trip packing (sectioned) and single-template editing
  - Provides shared toolbar, user selector, summary bar
  - Manages global add/edit state
- `SectionedPackingListView`: Shows items grouped by PackingList with collapsible sections
  - Persists collapse state via `SectionCollapseStateManager` (keyed by list `uuid`)
- `UnifiedPackingListView.swift` no longer has that struct; it hosts `UserSelector`, `PendingPackTracker`, `EmptyStateView`, `PackedItemsSection`
- Rows share `ItemRowViews.swift` components (Reminders-style editing):
  - `NewItemRow`: Inline add row rendered inside the target section; Return saves and keeps the row open, Return on empty or blur closes it (typed text is saved). Count/packer/section live in the container's accessory bar above the keyboard
  - `EditableItemRow`: Inline edit; commits on Return, blur, or disappear; backspace on empty name deletes the item
  - `UnifiedItemRow`: Display item with swipe-to-reveal delete and full-swipe delete
  - `AddItemTapZone`: Blank area at the end of a section/list; tap starts adding there (or finishes adding)
- `PendingPackTracker` (in UnifiedPackingListView.swift): checked items stay in place ~1.5s (tap again to undo) before moving to Packed

### Special Components

**ML Integration (Packing Engine):**
- `PackingEngineCore.swift` uses CoreML's `ProductSuggestionModel`
- Categorizes items: Clothing, Electronics, Toiletries, Task, other
- API is `PackingEngine.interpretItem(itemName:)`, called only from `Item.create`, which currently has no callers — new items are not categorized yet (ROADMAP.md 5.2)

**Weather Integration:**
- `WeatherUtilities.swift` + `TripLocation.swift` handle weather fetching
- Async/await pattern, caching with 1-hour TTL
- Only fetches for trips within 5 days of start date
- Use `getTripWeather(for:)` / `getCurrentWeather(for:)` / `getWeatherForecast(for:)` on TripLocation

**Notifications:**
- `NotificationUtilities.swift` wraps UNNotification permission handling
- Day-of packing notification at 8 AM (hardcoded) on trip start date, gated by `showingNotifications`
- Check/request permissions before scheduling

**Purchase Management (Plus):**
- `PurchaseManager.swift` + RevenueCat SDK; read `purchaseManager.isPlusActive`
- Plus gates the AI packing assistant and Unsplash search + Load More (free users get one 25-photo page for their destination, no search bar). There is no trip limit
- New trips auto-pick a random Unsplash cover photo in `TripEditView` (Worker `/v1/photos/random`, not gated) unless Settings → Default Cover (`defaultTripCover`) is Map
- Settings opens with `PlusSettingsSection` (upsell card, or an Active row → Customer Center); trip preferences go in its `TripSettingsSection`
- AI and Unsplash go through a Cloudflare Worker (`WORKER_URL`), which verifies the RevenueCat entitlement server-side

**AI Assistant:**
- `Views/AI/`, `ViewModels/AIAssistantViewModel.swift`, `Services/AIAssistantService.swift`, `Services/AITripContextBuilder.swift`
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
├── Services/            # Worker clients (AI)
├── CoverPhoto/          # TripCoverPhoto model, library/Unsplash pickers, loader, BlurHash
├── Views/
│   ├── Model Views/     # Entity-specific views (Trip/, PackingList/, DefaultPackingList/, Item/, Users/)
│   ├── AI/              # AI assistant sheet/panel
│   ├── Shop/            # Plus paywall/CTA
│   ├── Location/        # MKLocalSearchCompleter location search
│   ├── Weather/         # WeatherChip
│   ├── General/         # Shared UI components
│   ├── Onboarding/      # First launch flow
│   └── Settings/        # App settings + Developer Menu
├── Utilities/           # Cross-cutting concerns (Color, Calendar, Style, Purchase, etc.)
└── PackingEngine/       # ML categorization
scripts/run-on-device.sh # Build, install, launch on a physical iPhone (works over Wi-Fi)
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
- Use `#Preview(traits: .sampleData)`. (`PreviewContainer.swift` is unused)
- Don't use `Trip.sampleTrip` in new previews — it's a global model that schedules real notifications

**SwiftData Container Setup** (`User` is reached through relationships):
```swift
ModelContainer(for: Trip.self, TripLocation.self, PackingList.self, Item.self, TripCoverPhoto.self)
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
