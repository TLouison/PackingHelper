# HIG Audit — 2026-10-22

Static read of the SwiftUI sources against the Human Interface Guidelines (general, *Designing for iOS*, *Designing for iPhone Duo*). Nothing was run on device, so contrast and tap-target sizes are estimates from the code. Paths are relative to `PackingHelper/`. `PLDE/` = `Views/Model Views/PackingList/PackingListDetailEdit/`.

Severity: **High** = a core HIG principle (accessibility, adaptivity, data safety) is broken for some users. **Medium** = a clear departure from platform conventions. **Low** = polish.

## Status (updated 2026-10-22)

| Item | Status |
|------|--------|
| H1 orientation | **Won't fix**: portrait-only iPhone confirmed fine; works unfolded |
| H2 VoiceOver controls | Done: section header Button + header trait + expanded value, weather chip a11y element, packer cells Buttons, trip cards button trait + Delete action, color swatch names + selected trait, packer selector selected trait, onboarding page position |
| H3 tap targets | Done: header Add/Edit 44×44 (header is now 44pt tall), stepper and checkbox hit areas widened via `contentShape` without changing layout |
| H4 trip detail | Done: regular-width portrait scrolls when it doesn't fit; compact hero is 45% of height, clamped 240–380 |
| H5 contrast | Done: packed rows `.secondary` text, no 60% row fade, checkbox `.secondary`; packer pills use the full color with black/white text picked by luminance (`foregroundStyle(contrastingWith:)`) |
| M1 Liquid Glass | Done (approved variant): `.roundedBox()` uses a standard material; only the trip card info bar (over photo/map) keeps glass via `.glassRoundedBox()` |
| M2 FAB | Done: replaced by bottom-bar "Add Item" toolbar item |
| M3 ellipsis menu | Done: renamed "Sections", symbol `list.bullet.rectangle` |
| M4 toolbar titles | Done: Done and AI buttons are now `Label`s |
| M5 Reduce Motion | Done: onboarding crossfades, trip pager drops scale, AI panel slide is instant. (Map shimmer never actually animates, so it was left alone) |
| M6 onboarding | Won't change (decided); only the a11y and Reduce Motion fixes went in |
| M7 discard changes | Done: TripEditView blocks swipe-dismiss with unsaved changes; Cancel asks first |
| M8 Plus copy | Deferred to ROADMAP §2 |
| Low items | Open |

---

## High

### H1. iPhone is locked to portrait, but HIG says to build the app to resize
`PackingHelper.xcodeproj/project.pbxproj:319,357`: `UISupportedInterfaceOrientations = Portrait PortraitUpsideDown`.
- The iPhone Duo HIG says: *"Build your app to resize… Avoid fixed widths and display-specific dependencies"* and *"Maintain the same functionality across device poses."* The *Designing for iOS* page also lists device orientation among the appearance changes an app should *"adapt seamlessly"* to.
- The app already has landscape layouts: `TripListScrollView` shelf, `TripDetailView.landscapeLayout`, and `WidePackingColumns`. Today the iPhone plist doesn't allow them.
- Memory notes say all iPhone orientations were approved on 2026-10-21, but the build setting hasn't been changed yet.
- `PortraitUpsideDown` on iPhone is ignored on Face ID devices, so it adds nothing.
- **Fix:** list all four orientations for iPhone, then test each Duo pose in Xcode's preview.

### H2. Tappable elements that VoiceOver and Switch Control can't use
These use `onTapGesture` or bare `Color` views instead of a `Button`, so they expose no button trait and no action:
- `PLDE/Shared/PackingListSectionHeader.swift:56`: the section collapse/expand control (the list name). VoiceOver users can't collapse a section, and the header has no `.isHeader` trait.
- `Views/Weather/WeatherChip.swift:33,63`: tapping the weather icon reveals temperature and UV. VoiceOver can't reach that information, and sighted users have no cue that it's tappable. HIG says not to hide information behind gestures with no affordance.
- `Views/Model Views/Users/UserGridView.swift:37`: packer cells.
- `Views/Model Views/Trip/TripList/TripListScrollView.swift:223`: trip cards are a `Color.clear` tap layer under a combined element with no `.isButton` trait. Activation probably works by hit-test luck, but VoiceOver never announces the card as a button.
- `Views/General/UserColorPicker.swift:14–39`: the swatches are `Button { } label: { color }` with no label, so VoiceOver reads each one as just "Button". The selected swatch is shown only by a stroke, with no `.isSelected` trait. This picker is in onboarding, so a VoiceOver user's first screen is unusable.
- `PLDE/UnifiedPackingListView.swift:24–43` (`UserSelector`): selection is shown only by scale and opacity, with no `.isSelected` trait.

### H3. Tap targets under 44×44 pt in the main packing flow
- `PLDE/Shared/PackingListSectionHeader.swift:75–94`: the **+** and **pencil** buttons use `.imageScale(.medium)` with `.plain` style and no padding, so each target is roughly 20–24 pt. They sit next to each other and next to a 26 pt gauge, which makes mis-taps between Add and Edit likely.
- `PLDE/Shared/ItemRowViews.swift:94,110`: the count stepper −/+ targets are 32×32.
- `PLDE/PackingListContainerView.swift:612`: the Plus badge on the AI button uses a fixed 10 pt glyph (decoration only, but it doesn't scale).
- **Fix:** add `.frame(minWidth: 44, minHeight: 44)` with `.contentShape`, or use `.buttonStyle(.borderless)` with `controlSize`. Folding Add and Edit into the header's existing context menu would also clear space.

### H4. Regular-width trip detail can't scroll, so content clips at large Dynamic Type or on short windows
`Views/Model Views/Trip/TripDetail/TripDetailView.swift:161–182` (`portraitLayout`) is a plain `VStack` with no `ScrollView` or `ViewThatFits` fallback, unlike `landscapeLayout`. With a large text size, or on the unfolded Duo in a short pose (folded like a book, Split View), the packing and info cards get compressed or clipped. HIG requires layouts to adapt to Dynamic Type, and the Duo page says to *"provide access to the same controls and content regardless of how someone holds or views the device."*
- On compact width, `compactHeroHeight = 380` (`:50`) is fixed. The Duo outer display is *"wider and shorter"* than other iPhones, so a 380 pt hero takes most of the screen there. Size it relative to the container instead.

### H5. Low-contrast text and controls
- Packed items render `.gray` text (`ItemRowViews.swift:424`) and then the whole row gets `.opacity(0.6)` (`:524`). Gray at 60% on a white background falls well below WCAG AA (4.5:1). HIG asks for at least 4.5:1, and `.secondary` or `.tertiary` labels alone would read as "done".
- The unchecked checkbox uses `.gray.opacity(0.5)` (`ItemRowViews.swift:34,174,404`), so the circle boundary is about 1.5:1 against the background.
- `Models/User.swift:131–145` (`pillIcon`): white `caption2` small-caps text on `userColor.opacity(0.6)`. With yellow, green, teal, or orange, contrast is around 1.5–2:1. That pill is the packer filter in the packing view.
- **Fix:** use semantic styles (`.secondary`, `.tertiary`) and avoid stacking opacity. Pick black or white text based on the user's color, or use a solid tint.

---

## Medium

### M1. Liquid Glass applied to the content layer
`Utilities/ViewModifierUtilities.swift:18` (`Box`): `.box()` and `.roundedBox()` apply `.glassEffect` to every content card, including trip cards, trip-detail cards, template rows, review cards, and the Plus CTA. HIG reserves Liquid Glass for the controls and navigation layer that floats above content, and says to avoid it on content itself because glass on glass hurts legibility and hierarchy. Use a standard background for content cards (`.background(.background.secondary, in: .rect(...))`) and keep glass on floating controls such as the weather chip and accessory bar.
- Related: `PLDE/Shared/PackingSummaryBar.swift:44–58` is an opaque `systemBackground` bar with a drop shadow that stacks above the floating tab bar and clashes with the system scroll-edge effect.

### M2. A floating action button instead of a toolbar action
`PLDE/PackingListContainerView.swift:340` adds a 60 pt bottom-right `plus.circle.fill` FAB. That's a Material Design pattern, not an iOS one; on iOS, primary actions go in the toolbar. On the Duo, toolbars and tab bars move to the side, while the FAB stays bottom-right where it competes with them and has no title for the overflow menu. It also hardcodes `.blue` instead of the app tint. **Fix:** a `ToolbarItem(placement: .bottomBar)` with `Button("Add Item", systemImage: "plus")`. The system handles the vertical layout from there.

### M3. Custom overflow menu
`PLDE/PackingListContainerView.swift:645`: `Menu { … } label: { Label("Options", systemImage: "ellipsis.circle") }`. The Duo HIG says: *"Use the system overflow menu. If your app has its own overflow menu, move those actions into the system menu… Reserve the ellipsis symbol for overflow."* When the vertical bar overflows, this becomes an ellipsis inside an ellipsis. Make Create Section, Apply Template, and Reorder separate toolbar items with `visibilityPriority`, or give the menu a distinct symbol.

### M4. Toolbar buttons without titles
- `PLDE/PackingListContainerView.swift:586`: the Done button while adding is `Image(systemName: "checkmark")` with only an a11y label. Use `Button("Done", systemImage: "checkmark", role: .confirm)`, as `SettingsView.swift:197` already does.
- `:610`: the AI button is an image-only label.
- The Duo HIG says: *"Provide both a title and a symbol for each toolbar item… the system uses the title in overflow menus and expanded forms."* Without titles, overflowed items appear blank.

### M5. Reduce Motion is never checked
There are zero references to `accessibilityReduceMotion`. Motion that should be reduced or swapped for a crossfade:
- `TripDetail/TripDetailHeroView.swift:61–62`: a `repeatForever` shimmer sweeping ±400 pt.
- `TripListScrollView` `scrollTransition` scaling.
- Onboarding page slides (`OnboardingView.swift:108–150`), `.symbolEffect(.bounce)` on Add buttons, and the 1.3× scale on the user selector.
SwiftUI doesn't adapt custom `withAnimation` or transitions automatically. Read the environment value and fall back to `.opacity`.

### M6. Onboarding is long, mandatory, and partly a tutorial
`ContentView.swift:46–52` plus `Views/Onboarding/OnboardingView.swift`: six non-dismissible pages before the app is usable. Two of them (Plan Your Trips, Packing Templates) are pure feature explainers. The HIG onboarding guidance says to keep onboarding brief, let people start using the app quickly, and teach in context rather than through upfront tutorials. Other issues:
- The page dots (`:88–95`) are plain `Circle`s, so VoiceOver gets no page position.
- A custom "Back" button and a custom drag gesture (`:63–80`, `:152–169`) replace a `NavigationStack`, and the drag doesn't mirror in right-to-left languages.
- **Suggestion:** keep Name (required, because the app needs a `User`), make Color and Home Base optional or move them to Settings, and drop the two explainer pages in favor of empty-state copy. `ContentUnavailableView` already does that well in `TripListView`.

### M7. Swiping down on the edit sheet discards changes
`TripEditView` (already ROADMAP 10.9). HIG for sheets: when dismissing would lose changes, confirm first. Use `.interactiveDismissDisabled(hasChanges)` and show a "Discard Changes?" confirmation dialog on Cancel.

### M8. Paywall CTA promises features Plus doesn't include
`Views/Shop/PackingHelperPlusCTA.swift:130,190`: "Get unlimited trips, custom templates, and more". Plus actually gates only AI and Unsplash. This is already in ROADMAP §2, but it's worth raising in priority: HIG asks for accurate in-app purchase descriptions, and App Review guideline 3.1.1/2.3 rejects misleading claims.

---

## Low

- **Fixed text sizes that skip Dynamic Type:** `PackingHelperPlusCTA.swift:232` (16), `TemplateAnimationView.swift:140,146` (16/14), `PLDE/PackingListContainerView.swift:614` (10). The large 44–80 pt `system(size:)` hero glyphs are decorative, so those are fine.
- **Hardcoded `.blue` instead of the app tint:** checkbox, count badge (`ItemRowViews.swift:126`), summary bar progress, FAB, onboarding Continue. HIG says to use one consistent key color. Use `.tint` / `.accent`.
- **Custom row swipe actions** (`ItemRowViews.swift:345–378`) use a fixed negative offset, so they don't flip in right-to-left languages. They do have `accessibilityAction`s, which is good.
- **Notification permission** is requested inside `Trip.createDayOfPackingNotification()` (`Models/Trip.swift:407`) with no explanation first. HIG says to ask in context and explain the benefit. It's behind `showingNotifications`, so fix it with ROADMAP 4.2.
- **Toolbar placement override:** `readsVerticalToolbar` moves Add and Edit to `.bottomBar` in the vertical bar. The Duo HIG allows refinement but says *"in general, don't override the default bar placement"*. This is fine as long as positions stay consistent across poses.
- **`.ignoresSafeArea(.container, edges: .top)` with the vertical toolbar** (`TripDetailView.swift:119`): the hero image can go under the outer camera's reserved region. That's acceptable for full-bleed imagery, but check that the weather chip and title never land there.
- **Section header icon** `square.on.square` (`PackingListSectionHeader.swift:46`) has no a11y label ("from template").

---

## Already compliant (keep doing)
- System `TabView`/`Tab`, `NavigationStack`, sheets, `ContentUnavailableView` for empty states, and confirmation dialogs or alerts with `.destructive`/`.cancel` roles before destructive actions.
- Layout keys off `horizontalSizeClass` and container geometry. There's no `UIScreen.main`, `userInterfaceIdiom`, or orientation API, and the launch screen is set, so the app passes the app-resizability prerequisites apart from H1.
- Vertical toolbar awareness (`toolbarVerticalEdge`), hand-off of the AI panel to a sheet on fold, and `WidePackingColumns` splitting at exactly 50%, which lines up with the hinge as the Duo HIG recommends.
- Good accessibility coverage on item rows: labels, custom actions for delete and add-to-template, combined elements, and adjustable framing on the cover photo.
- Semantic text styles almost everywhere. Appearance follows the system.

## Suggested order
H1 → H2 → H3 → H5 → H4 → M2/M3/M4 (one toolbar PR) → M5 → M1 → M6 → rest.
