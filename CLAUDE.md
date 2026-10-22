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

The app uses SwiftData with four core models that have specific relationships:

**Trip** (root entity)
- Properties: `name`, `startDate`, `endDate`, `type` (plane/car/train/boat/ferry), `accomodation`
- Has-many: `lists` (PackingList, cascade delete)
- Has-one: `origin`, `destination` (TripLocation)
- Extensions provide rich computed properties: `.status`, `.packers`, `.totalItems`, `.packedItems`
- Status calculation based on dates: `.upcoming`, `.departing`, `.active`, `.returning`, `.complete`

**PackingList**
- Properties: `name`, `type` (.packing or .task), `template`, `countAsDays`, `isDayOf`
- Belongs-to: `trip` (Trip), `user` (User)
- Has-many: `items` (Item, cascade delete)
- Self-referencing: `appliedFromTemplate` (for template system)
- Templates can be copied to specific users/trips

**Item**
- Properties: `name`, `category` (ML-categorized), `count`, `isPacked`
- Belongs-to: `list` (PackingList)
- Simple CRUD with static copy methods

**User**
- Properties: `name`, `created`, `profileImageData`, `colorHex`
- Has-many: `lists` (PackingList, cascade delete)
- Rich UI components: pill icon, profile view, initial icon with glass effect

**TripLocation**
- Properties: `name`, `latitude`, `longitude`
- Cached weather data with 1-hour TTL
- Async methods for current weather and 5-day forecasts
- Custom Codable for encoding/decoding

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
- `@AppStorage` for user preferences (dark mode, onboarding status, view modes)
- Navigation uses `NavigationStack` with type-safe `NavigationPath`

**Focus State Management:**
- IMPORTANT: When using text fields with keyboards, manage focus at the parent level
- Pass `@FocusState.Binding` to child views (NewItemRow, EditableItemRow)
- Always dismiss keyboard BEFORE animating view removal to prevent layout shifts
- Pattern: `isTextFieldFocused = false` → `withAnimation { ... remove view ... }`
- See PackingListContainerView, UnifiedPackingListView, SectionedPackingListView for examples

**Extensions:**
- Models have extensive extensions grouping related functionality
- Computed properties for derived data (`.incompleteItems`, `.completeItems`, `.progress`)
- Sample data extensions for SwiftUI previews

### Navigation Hierarchy

```
ContentView (TabView)
├── TripListView (Trips tab)
│   ├── TripListRowView
│   └── NavigationLink → TripDetailView
│       ├── TripDetailHeroView (overview + settings)
│       ├── TripDetailPackingView
│       │   └── PackingListContainerView
│       │       ├── UnifiedPackingListView (flat item list)
│       │       └── SectionedPackingListView (grouped by list)
│       ├── TripDetailForecastView (weather)
│       └── TripDetailInfoView (details)
├── DefaultPackingListView (Templates tab)
├── UserGridView (Packers tab) [feature flagged]
└── SettingsView (Settings tab)
```

**Packing List Views (Critical Component):**
- `PackingListContainerView`: Smart switcher between unified/sectioned modes
  - Provides shared toolbar, user selector, summary bar
  - Manages global add/edit state
- `UnifiedPackingListView`: Shows all items in flat list (packed/unpacked sections)
  - Used for unified mode and single-list detail editing
  - Supports .unified, .detail, .templating modes
- `SectionedPackingListView`: Shows items grouped by PackingList with collapsible sections
  - Persists collapse state via `SectionCollapseStateManager`
- Both views share `ItemRowViews.swift` components (Reminders-style editing):
  - `NewItemRow`: Inline add row rendered inside the target section; Return saves and keeps the row open, Return on empty or blur closes it (typed text is saved). Count/packer/section live in the container's accessory bar above the keyboard
  - `EditableItemRow`: Inline edit; commits on Return, blur, or disappear; backspace on empty name deletes the item
  - `UnifiedItemRow`: Display item with swipe-to-reveal delete and full-swipe delete
  - `AddItemTapZone`: Blank area at the end of a section/list; tap starts adding there (or finishes adding)
- `PendingPackTracker` (in UnifiedPackingListView.swift): checked items stay in place ~1.5s (tap again to undo) before moving to Packed

### Special Components

**ML Integration (Packing Engine):**
- `PackingEngineCore.swift` uses CoreML's `ProductSuggestionModel`
- Categorizes items: Clothing, Electronics, Toiletries, Task, other
- Call `PackingEngineCore.interpretItem(itemName:)` when creating items

**Weather Integration:**
- `WeatherUtilities.swift` + `TripLocation.swift` handle weather fetching
- Async/await pattern, caching with 1-hour TTL
- Only fetches for trips within 5 days of start date
- Use `.fetchCurrentWeather()` and `.fetchDailyForecast()` on TripLocation

**Notifications:**
- `NotificationUtilities.swift` wraps UNNotification permission handling
- Trips create day-of packing notifications at 8 AM on trip start date
- Check/request permissions before scheduling

**Purchase Management:**
- `PurchaseManager.swift` + RevenueCat SDK integration
- `SubscriptionAwareButton` checks trip limit (3 free trips max)
- Feature flag `FeatureFlags.enableSubscriptionUI` currently disabled

### Feature Flags

Located in `FeatureFlags` struct (check for current values):
- `enableRecommendations`: ML-based packing suggestions
- `enableMultiplePackersUI`: Multi-user interface components
- `enableSubscriptionUI`: In-app purchase flows

Use these to conditionally show/hide features in development.

### File Organization

```
PackingHelper/
├── Models/              # SwiftData models
├── ViewModels/          # Lightweight view models (@Observable)
├── Views/
│   ├── Model Views/     # Entity-specific views (Trip/, PackingList/, Item/, Users/)
│   ├── General/         # Shared UI components
│   ├── Onboarding/      # First launch flow
│   └── Settings/        # App settings
├── Utilities/           # Cross-cutting concerns (Color, Calendar, Style, etc.)
└── PackingEngine/       # ML categorization
```

**Naming Convention:**
- Views: `{Entity}{Action}View.swift` (e.g., TripEditView, PackingListDetailView)
- Row components: `{Entity}RowView.swift` or `{Purpose}Row.swift`
- Sheets/modals: Often in `/Sheets/` subdirectory

### Data Persistence Notes

**Migration:**
- App performs legacy migration on first launch (`migrateDayOfLists()`)
- Converts old "Day-of" list type to `isDayOf` boolean flag
- Flag-controlled via `@AppStorage("hasMigratedDayOfLists")`

**Preview Infrastructure:**
- `PreviewContainer.swift`: Sets up ModelContainer for SwiftUI previews
- `SampleData.swift`: Generates mock trips, lists, items, users
- Always use `PreviewContainer.preview` for preview data

**SwiftData Container Setup:**
```swift
ModelContainer(for: Trip.self, TripLocation.self, PackingList.self, Item.self)
```

### Critical Dependencies

- **RevenueCat:** Subscription management (API key in `PackingHelperApp.swift`)
- **StoreKit:** In-app purchases (.storekit configuration file)
- **WeatherKit:** Weather forecasts (requires entitlement)
- **CoreML:** ProductSuggestionModel must be included in project
- **MapKit:** Location display and geocoding

### Known Constraints

- App requires at least one User to display trips
- Free users limited to 3 active trips (enforced via RevenueCat)
- Weather data only fetched within 5 days of trip start
- iOS 26+ minimum deployment target
- Some features currently disabled via feature flags (see FeatureFlags struct)
