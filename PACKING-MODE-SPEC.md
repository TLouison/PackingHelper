# Packing Mode — Spec

A full-screen "packing in progress" view meant to be stood up while you pack: on iPhone Duo
in tent pose, propped on a dresser, or just held. It shows the trip, the current list, the
next one or two items to pack, and a ring gauge of how close you are to done. You pack items
by tapping them or by voice.

Mockups: `/tmp/duo-mock/tent.html` (layout options), `tent2.html` (states and voice); the
final entry, skip, and name-matching frames were reviewed in chat on 2026-10-30. Option A
("Ring + Up Next") was chosen.

Paths are relative to `PackingHelper/`.

## Summary of decisions

| Topic | Decision |
| --- | --- |
| Name | **Packing Mode** |
| Entry | Toolbar button on trip detail and the trip packing view. No automatic entry (iOS has no pose API; see §9) |
| Lists included | Everyday **packing** lists only. No task lists, no day-of lists |
| Order | Next unpacked item in list order (trip list order, then item order). Finish one list, move to the next |
| Packer | With `showingMultiplePackers` on, the user picks who they're packing for before starting. Off: everything (all items belong to the main user) |
| Gauge | Outer ring = progress across the included lists for the chosen packer. Inner ring = current list |
| Done | Green "All Packed" state, with a pointer to day-of items if any are left |
| Pack by touch | Tap a row packs it, with the same ~1.5 s Undo window as the packing view |
| Skip | Long-press → Skip for Now, or say "skip". Moves the item to a temporary **Skipped** list at the end of the queue. Never saved |
| Voice | On-device listening for a few commands plus item names. Optional read-aloud of the next item |
| Session state | Starts fresh every time: no saved packer choice, no saved skips |
| Layout | `ArrangementView` with `.split`: ring is primary, info is secondary |

## 1. Entry and exit

- **Trip detail** (`TripDetailView`) and **trip packing** (`PackingListContainerView+Toolbar.swift`,
  `tripToolbar`) each get a toolbar item: `Button("Packing Mode", systemImage: <TBD>)`.
  Use a `Label` with both title and symbol, so iPhone Duo can show it in the side bar or put it
  in the overflow menu. Give it a lower `visibilityPriority` than the AI assistant and Edit Mode.
- Hidden when the trip has no unpacked items in an included list (nothing to do). If every
  included item is already packed, the button still shows and opens straight to All Packed.
  If there are no included items at all (only tasks or day-of lists), hide it.
- Presented with `.fullScreenCover`. It is not pushed: it replaces the whole screen, has no
  back stack, and must not sit inside the packing view's `NavigationStack`.
- Close is a `ToolbarItem(placement: .cancellationAction)` in the cover's own `NavigationStack`,
  so iPhone Duo places it first in the vertical bar.
- Template packing (single-list template editing) does not get Packing Mode.

## 2. The queue

The queue is built from live model data each time the view updates, not snapshotted, so items
added, renamed, deleted or packed elsewhere (another device, CloudKit later) show up correctly.

1. **Lists:** `trip.sortedLists(of: .packing)` filtered to `!isDayOf`. Same order as the chip rail.
2. **Items per list:** unpacked items for the chosen packer, in the list's item order (the same
   sort the Focus pages use, `sortOrder`).
3. **Skipped:** items the user skipped this session are removed from their list's spot and
   appended, in skip order, as a final virtual list named **Skipped**.
4. The **current list** is the list of the first queue item. The **up-next rows** are the first
   two queue items. Row 2 may come from the next list; it is still shown (it's useful to see
   what's coming), and the list name in the header always refers to row 1.
5. Items in the Pending window (just packed, Undo still showing) stay in place as row 1 until the
   window ends, the same as `PendingPackTracker`.

Skipped list rules:
- Shown only when it has items and every real list is done.
- Skipping an item while it's in Skipped moves it to the end of Skipped.
- If the only items left are all in Skipped, they cycle. That's fine: the user can close.
- Packing a skipped item by any means (tap, voice, another screen) removes it from Skipped.
- Kept in memory on the session object only (`Set<UUID>` of item `uuid`s plus an order array).
  Lost on close, by design.

## 3. Packer selection

Only when `FeatureFlags.shared.showingMultiplePackers` is on.

- On entry, a full-screen picker ("Who are you packing for?") shows every user with items on
  the included lists, each with "N left" or "All packed". Tapping one starts the session.
- If only one user has included items, skip the picker and use them.
- Their avatar stays in the vertical bar under the mic button. Tapping it reopens the picker.
  Switching packer clears the Skipped list.
- Filtering: `item.user == packer`. See open question 1 for items with no user.
- With the flag off, there is no picker and no avatar; the queue holds every included item.

## 4. Gauge

- **Outer ring** (teal, the app accent): packed / total for the included lists and the chosen
  packer. This is not the whole-trip number on trip detail, because day-of and task items are
  excluded; otherwise the ring could never reach 100%. The center shows the percentage and
  "23 of 34".
- **Inner ring** (thinner, white at ~85% opacity): packed / total for the current list. The list
  header also shows "4 left".
- Both rings move as soon as an item is packed (when it enters Pending), not when the
  Undo window ends.
- When a list finishes, the inner ring fills, flashes green, then resets to the next list. A
  small green "Toiletries done" line shows above the trip name for ~2 s.
- Built on `Gauge` or a pair of `PackProgressRing`-style views. The ring sits in a square sized
  to the primary pane, not a fixed point size. Use `.animation(.packingSpring, value:)`.
- Respect Reduce Motion: no flash, just a cross-fade.

## 5. States

1. **Packing:** ring pane + header (trip name, list name with "N left") + "Up Next" + two rows.
   Row 1 large (about title size), row 2 smaller and secondary. Count badge when `count > 1`.
2. **Pending:** row 1 shows a filled check, struck-through name and an Undo button for ~1.5 s,
   then slides up.
3. **List finished:** see §4.
4. **Skipped:** list header shows the orange skip glyph + "Skipped". Same rows.
5. **All Packed:** both rings green with a check in the center. "All Packed" + "34 items ready
   to go". If day-of packing items are left: "3 more on Day Of for the morning" (DayOfPacking
   symbol). If tasks are left: "2 tasks left". A Done button closes. Listening stops on its own.
   Matches the existing `.green` tint at 100% (`TripDetailPackingProgressView`).
6. **Packer picker:** see §3.

## 6. Layout

```swift
ArrangementView {
    PackingModeGauge(...)      // primary
} secondary: {
    PackingModeUpNext(...)     // secondary
}
.arrangementViewStyle(.split)
```

- Tent pose / any wide-and-short scene: ring leading, info trailing.
- Inner display partly folded: the split puts one pane on each side of the fold, with no extra code.
- Portrait: ring on top, info below.
- `ArrangementView` is the cover's root content. Nothing that lays out children (no
  `ScrollView`, `List`, or grid) goes around it, and no `NavigationStack` or `TabView` goes inside it.
- **Must check on device:** Apple's docs say a split arrangement on a *closed* iPhone Duo in
  landscape **shows only the primary view**. If tent pose counts as that case, the info pane
  disappears. Fixes to try in order: `.split.axes(...)`, then `.overlay` with
  `overlayArrangementEdge`, then a plain `HStack`/`VStack` picked by aspect ratio.
- Size type relative to the scene (`ViewThatFits` or a scale from the pane size), not fixed
  points. It has to read from across a room on the outer display and not look huge on iPad.
  Long item names: two lines max for row 1, one for row 2, tail truncation.
- Dark background regardless of system appearance? See open question 3.
- Keep the screen awake: `UIApplication.shared.isIdleTimerDisabled = true` on appear, `false`
  on disappear and when the scene goes to the background.

## 7. Touch

- Tap row 1 or row 2 → pack (through the session's pending tracker; see §10).
- Tap a Pending row or its Undo → unpack, immediately.
- Long-press a row → menu: **Pack**, **Skip for Now**.
- The rows are buttons, not drag targets. No swipe actions (they're too easy to trigger by accident on a
  propped-up phone).
- Haptic on pack (`.sensoryFeedback(.success, trigger:)`) and on list completion.

## 8. Voice

### 8.1 Listening

- Mic toolbar item under Close (`Label("Listen", systemImage: "mic")`, filled/teal when on).
  Off by default each session.
- First tap asks for microphone permission (and speech permission if the API needs it; check this).
  If permission is denied, the button opens an alert pointing to Settings.
- On-device only: `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26), fed from an `AVAudioEngine`
  input tap. Download the language asset with `AssetInventory` if it's missing; show "Getting
  voice ready…" in the caption while it downloads. No server and no Plus gate.
- Give the analyzer the queue's item names and the command words as contextual strings
  (`AnalysisContext`) to improve recognition. Refresh when the queue changes.
- Act on finalized results only; use partial results just to animate the waveform.
- Stops on: mic toggled off, All Packed, close, scene going to the background, audio
  interruption. Restarts after an interruption ends only if it was on.
- The system orange mic indicator is expected while listening.

### 8.2 What it understands

Matching order for each finalized phrase (normalized with `AITripContextBuilder.matchKey`):

1. **Commands**, whole phrase:
   - "packed", "got it", "check" → pack row 1
   - "skip", "later", "skip it" → skip row 1
   - "undo" → undo the most recent pack from this session (even after the Pending window,
     as long as the item is still packed)
   - "what's next", "next" → speak row 1 (always, even with read-aloud off)
2. **Item name**: exact `matchKey` match against every queue item (not just the two rows),
   then "packed X" / "X packed" forms. A match packs it. If it isn't in the two rows, it's shown
   briefly as row 1 in the Pending state with Undo, then the queue goes on.
3. **Several items match** (e.g. two "Charger" items in different lists): don't pack. The caption asks
   "Charger: Phone or Watch?" using the list names; the next phrase that matches one picks it.
4. **No match**: caption shows "Didn't catch that" for ~2 s. Nothing happens.

An item named like a command (an item literally called "Skip") is reachable only by tap.

### 8.3 Caption

A capsule at the bottom of the info pane shows a waveform, "Heard", the phrase, and the result
("· Packed", "· Skipped"). It fades after ~2 s. VoiceOver announces the result.

### 8.4 Read aloud

- A toggle in the overflow menu: "Read Next Item Aloud". Off by default; turning on the mic
  does not turn it on.
- `AVSpeechSynthesizer` says "Next: sunscreen, two" after each pack or skip, and "Toiletries
  done. Next list: Electronics" on list change.
- Audio session: `.playAndRecord`, `.defaultToSpeaker`, `.duckOthers` while either is active.
  Mute the recognizer while speaking so it doesn't hear itself.

### 8.5 Info.plist

Add `NSMicrophoneUsageDescription` ("Packing Mode listens for item names and commands like
"packed" so you can pack hands-free.") and `NSSpeechRecognitionUsageDescription` if
`SpeechAnalyzer` needs it (check).

### 8.6 Later, not in this spec

App Intents / App Shortcuts ("Mark packed in Packing Helper", "What's next in Packing Helper")
for packing from AirPods or with the screen off.

## 9. Tent detection (later, optional)

iOS has no API that reports the iPhone Duo pose. Apple's docs only offer size classes, scene
geometry, reserved regions, and `ArrangementView`. A possible heuristic: while the trip packing
view is open, the scene turns wide and short, and CoreMotion reports the device upright and
still for ~3 s → show a one-tap banner, "Start Packing Mode?". Never enter
automatically. Dismissing it turns it off for that trip. Test it on the Device Hub simulator before
building; holding the phone sideways produces the same geometry.

## 10. Architecture

New folder `Views/Model Views/PackingList/PackingMode/`:

| Type | Role |
| --- | --- |
| `PackingModeView` | The `.fullScreenCover` root: `NavigationStack`, toolbar (Close, mic, avatar, overflow), the picker or the arrangement, idle-timer handling |
| `PackingModeSession` | `@MainActor @Observable`. Holds the trip, packer, skipped order, pending tracker, last-packed stack for voice undo. Computes the queue, current list, ring values, and state. `pack(_:)`, `skip(_:)`, `undo()`, `handle(phrase:)` |
| `PackingModeGauge` | The two rings + center text |
| `PackingModeUpNext` | Header, rows, caption, list-done line, All Packed view |
| `PackingModePackerPicker` | §3 |
| `PackingModeListener` | Wraps `SpeechAnalyzer`, audio engine, permission, asset download. Emits finalized phrases and partial-result levels. No model access |
| `PackingModeSpeaker` | `AVSpeechSynthesizer` wrapper |

- Reuse `PendingPackTracker` as is (own instance on the session, not the `PackingEditor`'s, so
  Packing Mode doesn't affect the packing view underneath).
- Key skipped and last-packed items by `uuid`, not `persistentModelID` (CLAUDE.md).
- Pack/unpack goes through the same model path the packing view uses (set `isPacked`, save via
  the context), so trip detail's progress, the "left for today" line, and notifications stay
  right.
- No schema change.

## 11. Accessibility

- Rings: one accessibility element, "68 percent packed, 23 of 34. Toiletries, 4 left."
- Rows: buttons labeled "Toothbrush" / "Sunscreen, 2", hint "Double-tap to pack". Custom
  action "Skip for Now".
- Dynamic Type: the large sizes are already large; cap scaling at the accessibility sizes so
  row 1 still fits two lines.
- Reduce Motion: §4.
- Voice control features don't replace VoiceOver; both must work together (the listener
  pauses while VoiceOver is speaking? check this).

## 12. Edge cases

- Item deleted while it's row 1 or Pending → drop it from the queue; if it was in the voice-undo
  stack, remove it.
- List deleted, renamed, reordered, or converted to tasks/day-of while open → the queue
  rebuilds; the skipped set keeps only items still eligible.
- Item unpacked elsewhere → reappears in its spot in the queue.
- Packer switched → Skipped cleared, voice-undo stack cleared.
- Count > 1 → packing marks the whole item packed (same as the packing view); count is a badge only.
- App backgrounded → listening stops, idle timer restored; returning resumes the screen, not
  the mic.

## 13. Testing checklist (user runs)

Device Hub / iPhone Duo simulator: tent, closed portrait/landscape, inner flat
portrait/landscape, book fold, laptop fold. Check the split shows both panes in tent (§6), the
fold never cuts the ring or row 1, the vertical bar order (Close, mic, avatar), and that
long names truncate cleanly. Also check iPhone 17-class portrait and iPad.

## Open questions

1. **Items with no packer.** The intent is that every item has a packer, but `Item.user` is
   optional and two paths leave it `nil` today: `User.delete` nullifies the deleted user's items,
   and `TripEditView` applies shared (owner-less) templates with `applyDefaultLists(to: nil…)`,
   which leaves those items unassigned. Options: (a) fix both paths so items always get a packer
   (deleted user's items → main user; shared template items → main user) and add a ROADMAP
   item; Packing Mode then ignores the case. (b) Packing Mode folds `nil` items into every
   packer's queue, as `AITripContextBuilder.itemsBelonging` does. Recommendation: (a).
2. **SF Symbol** for the Packing Mode button.
3. **Appearance.** Force dark in Packing Mode (better for a lit bedroom, ring pops more), or follow the
   system like the rest of the app?
4. **"Undo" by voice** after the Pending window has ended. The spec allows it for the latest
   pack. Keep that, or limit it to the Pending window?
