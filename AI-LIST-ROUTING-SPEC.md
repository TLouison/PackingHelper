# AI Assistant: List Routing and Template Matches — Spec

Two additions to the trip-mode AI assistant:

1. **List routing.** Each suggestion goes to the trip list it belongs on (snorkel → Beach,
   "Charge phone" → the day-of tasks list), chosen by the model from the trip's actual lists
   and checked by the client.
2. **Template matches.** When one of the user's templates clearly fits the trip and isn't
   on it yet, the reply can offer it as a compact row that applies the whole template. The
   bar is high. The client sends the model only templates backed by a hard signal, and the
   model picks at most one, usually none.

Template mode (building a template) is unchanged.

Paths are relative to `PackingHelper/` unless prefixed `Workers/` (the `PackingHelperWorkers`
repo).

## Implementation status (2026-10-27)

| Part | State |
| --- | --- |
| §1 List routing | **Done**, app + Worker. Not compiled or tested on device yet |
| §4 Prompt layout / caching | **Done** (Worker). Not yet verified against the live API |
| Past trips cost cap | **Done**: ≤ 3 trips with similarity ≥ 3 in trip mode (template mode keeps its applied-first, then most-recent ranking). Built once per chat session |
| §2 Template matches | **Not started**. Nothing in §2 exists in code, including the starter prompt |

### What was built

**List routing (§1)**, with these changes from the original §1 text:
- **Short list ids.** `AITripList.id` is `L1`, `L2`, … in list order, per request, not the
  uuid (a uuid is ~25 output tokens per suggestion). `AITripList.listUUID` is not encoded. In
  `send()`, `AIAssistantViewModel.resolvingListIDs(_:sentLists:)` maps each reply's short ids
  back to uuid strings, using the lists from *that* request, before the entry is shown or
  saved. Unknown ids are cleared. `AISuggestedItem.listId` is a `var` for this. Saved chats
  hold uuids.
- **No-fit fallback never uses another list.** `fallbackList` packing → `trip.defaultPackingList`
  only (the old `?? lists.first` put toothbrushes on a Clothes-only trip's Clothes list). When
  it's missing, `destinationList` creates it on first add (`makeDefaultList` →
  `PackingList.createDefaultList`), the same way a missing Tasks list is made
  (`makeTasksList`).
- **Caption.** `AISuggestionDestination` (in `AISuggestedItemList.swift`) has `isNew`. The
  caption shows "New list: Default" / "New list: Tasks" when tapping would create the list,
  even on a one-list trip. Otherwise it names the list only when the trip has 2+ lists. The
  caption is hidden once the item is added. The "New list:" copy hasn't been approved yet.
- **Worker prompt.** Routing rules are in `TRIP_INSTRUCTIONS`, including "never put an item on
  a list whose name doesn't fit it" and "no fitting list and no default → leave `listId` out".
  The lists block ends with "They have no default list." when that's true. A 200-item cap is
  shared round-robin across lists (`listItemBudgets`).
- **Worker validation.** `index.ts` accepts `lists` (each needs a string `id`/`name` and a
  string `items` array) or the old flat `listNames` + `existingItems`. Drop the old shape once
  the app ships.

**Caching (§4).** `Workers/src/anthropic.ts` `buildRequestParts`:
- `system` = [instructions block, context block], each with `cache_control: ephemeral`.
- The last user message gets a third breakpoint.
- `currentState` (lists, other packers' items; template mode: the template's items) goes last
  as a `{role: "system"}` message. Haiku 5.5 supports this; the minimum cacheable prefix is 512
  tokens.
- Each call logs `usage mode=… in=… cacheRead=… cacheWrite=… out=…`.
- For the cache to hold, the app snapshots past trips for the session
  (`AIAssistantViewModel.pastTripsSnapshot`, keyed by the packer's `persistentModelID`; reset
  on New Chat and packer change).
  - `AITripContextBuilder.build(for:targetUser:weather:pastTrips:)` and
    `build(for:pastTrips:)` take past trips from the caller.
  - `AITripContextBuilder.pastTrips(for:…)` builds them.
- `User` has no `uuid` (CLAUDE.md now says so), hence `persistentModelID`.

### Files touched
- App: `Services/AIAssistantService.swift`, `Services/AITripContextBuilder.swift`,
  `Services/AIPastTripsBuilder.swift`, `ViewModels/AIAssistantViewModel.swift`,
  `Views/AI/AISuggestedItemList.swift`, `Views/AI/AIAssistantSheet.swift`, `CLAUDE.md`.
- Worker: `src/types.ts`, `src/index.ts`, `src/prompt.ts`, `src/anthropic.ts`, `README.md`.

### Before testing
1. **Deploy the Worker first.** The deployed Worker rejects the new app's requests, which
   have no `existingItems`.
2. Build the app.
3. Run the routing checks in §7 (1–3), plus:
   - **Short ids:** reorder lists after a reply arrives; captions still name the right lists.
   - **No Default list:** a Clothes-only trip shows "New list: Default" on toiletries, and a
     tap creates Default.
   - **Caching:** in the Worker log, `cacheRead` is most of `in` from the second message on.

### Next: §2 Template matches
Build it as specified, with these updates:
- List ids are now short (`L1`…). Use `T1`… for template candidates the same way, and map
  them back on receipt.
- Candidates go in `currentState`, not the cached context (§2c, §4).
- There's no `AITemplateCandidatesBuilder` yet, and `AIPastTripsBuilder.similarity` is still
  `private`.

---

## Summary of decisions

| Topic | Decision |
| --- | --- |
| Routing mechanism | Model returns `listId` per item: a short per-request id (`L1`, `L2`, …) that the client maps back to the list's `uuid` on receipt. Client validates it and falls back to today's rule |
| No good fit | Model leaves `listId` out. Default list (packing) / first everyday Tasks list (tasks), each created on first add if the trip lacks it; never some other list. The caption shows "New list: Default" for a list that would be created. The model never proposes other new lists |
| Kind mismatch | Packing item → tasks list, or task → packing list: ignore `listId`, use the fallback |
| Day-of lists | Valid targets when the item is clearly for the day you leave |
| Row display | Caption naming the destination list (`ListNameLabel`, with glyph) when the trip has 2+ lists or the list would be new ("New list: Default"). Long-press "Add to" override stays |
| List payload | `lists: [{id, name, kind, isDayOf, isDefault, fromTemplate, items}]` replaces `listNames` + `existingItems` |
| Template confidence | Client pre-filters to eligible templates with at least one hard signal and sends each signal along. Model picks ≤1 or none |
| Hard signals | (a) applied to a past trip with similarity ≥ 5; (b) a significant word of the template name is in the trip name or a list name; (c) ≥ 40% and ≥ 4 of its items already on the trip |
| Eligibility | Template, non-empty, not already applied to this trip, no trip list with the same name, owned by the selected packer or shared (ownerless) |
| Template payload | ≤ 5 candidates ranked by signal strength; name, kind, isDayOf, item count, ≤ 25 item names, signals |
| Prompt placement | Lists and template candidates change mid-chat, so both go in the Worker's uncached current-state system message (§4), never in the cached prefix |
| When shown | Inside an assistant reply, above the item sections. Once per template per conversation (an added or dismissed template is never offered again in that chat) |
| Row style | Compact row like a suggestion row: template glyph, name, "Template · reason", trailing xmark (dismiss) and + (add). Context menu: Add List / Not Now |
| Add action | Normal apply path (new linked list, `countAsDays` scaling, owner/packer assignment), skipping items the recipient already has (`matchKey`) |
| After add | Row shows a checkmark and "Added · N new items". No undo (delete the list normally) |
| Overlap with items | Prompt: when suggesting a template, don't also suggest its items |
| Prompt bar | Separate from the item rules: "only if highly confident it fits this trip's purpose; usually none" |
| Starter prompt | "Do any of my templates fit?", shown only when ≥ 1 candidate passes the pre-filter |
| Multiple packers off | `targetUser` is nil, so ownership doesn't filter and every template is eligible |

---

## 1. List routing

### 1a. Wire: request

`AITripContext` (`Services/AIAssistantService.swift`, `Workers/src/types.ts`):

- Remove `listNames` and `existingItems`.
- Add `lists: [AITripList]`, in `PackingList.sorted(..., .byCustomOrder)` order, **including
  lists with none of the packer's items** (so an empty Beach list can still receive items):

```swift
struct AITripList: Encodable {
    let id: String            // "L1", "L2", … in list order, per request (a UUID is ~25 output tokens per suggestion)
    let listUUID: UUID        // not encoded; maps the short id back on receipt
    let name: String
    let kind: String          // "packing" | "tasks"
    let isDayOf: Bool
    let isDefault: Bool
    let fromTemplate: String? // appliedFromTemplate?.name
    /// The packer's items plus unassigned ones on this list, packed or not (same scope as the old existingItems)
    let items: [String]
}
```

- Item scope is unchanged: `AITripContextBuilder.itemsBelonging(to:in:)`, grouped by list.
  Names are trimmed, deduped within the list by `matchKey`, and kept in `sortOrder`.
- `otherPackersItems` stays flat.
- In the Worker, the lists block replaces `listNames` + `existingItems` in `currentState` (the
  mid-conversation system message after the history; see §4), because it changes whenever an
  item is added.
- The 200-item cap (`MAX_EXISTING_ITEMS`) now applies across all lists in the Worker's prompt
  builder. It trims from the end of each list, round-robin, so no list is dropped entirely.

### 1b. Wire: response

`AISuggestedItem` gains `listId: String?`, decoded with `decodeIfPresent`. On receipt the view
model replaces the short id with the list's UUID string, using the `lists` from the request that
got this reply, and clears unknown ids. It's then persisted with the conversation like
`fromTrip`, so saved chats survive lists being added or reordered. In the Worker's `SUGGESTION_SCHEMA` it's an optional
string, left out of `required`.

### 1c. Prompt (`Workers/src/prompt.ts`)

The trip prompt replaces "Their lists" and "Already on their lists" with a lists block:

```
Their lists (id · name · kind):
- L1 · Default (everyday packing, default): Toothbrush, Phone charger, …
- L2 · Beach (packing, from template "Beach Weekend"): Swimsuit, …
- L3 · Before We Go (tasks, day-of): (empty)
```

Routing rules added to the trip instructions:

- Set `listId` to the list the item belongs on: match the list's name and purpose (snorkel
  gear → a Beach list; toiletries → a Toiletries list).
- Tasks go only on tasks lists, and things to pack only on packing lists.
- Day-of lists are for things done or grabbed the day they leave ("Charge phone", "Pack
  snacks for the car", "Take out trash"). Use one only when the item clearly belongs to that
  day.
- When nothing fits clearly, use the Default list for packing and leave `listId` out for
  tasks. Never invent an id.
- The dedupe rule stays: an item on any list covers every list.

Template mode ignores routing. The shared schema allows `listId`, but the template prompt
doesn't mention it, and the client ignores it there.

### 1d. Client resolution (`AIAssistantViewModel.destinationList(for:)`)

Order for a trip:

1. Explicit list from "Add to" (unchanged).
2. `suggestion.listId` (already mapped to a UUID) → a trip list whose `uuid` matches, and whose kind agrees
   (`.task` ↔ `.tasks`, `.packing` ↔ `.packing`).
3. Fallback: a task goes to the first everyday (not day-of) Tasks list, and packing goes to
   `defaultPackingList`. Either is created on first add if missing (`PackingList.createDefaultList`).
   Never `lists.first`: on a trip without a Default list that put toothbrushes on Clothes.

A deleted list, a stale id from a saved chat, or a hallucinated id all fall through to step 3.
The same resolver feeds the row caption, so the label always matches where the tap goes.

### 1e. UI (`Views/AI/AISuggestedItemList.swift`)

- Pass a `destination: (AISuggestedItem) -> PackingList?` closure (view model resolver).
- When `lists.count > 1`, the row's detail line ends with the destination via `ListNameLabel`
  at caption size, secondary style, e.g. "for Laptop · packed on Maui · Beach". When it's the
  only detail, it shows alone. Once added, the label is hidden like the rest of the detail.
- Category sections stay. A section's "Add all" (primary action) sends each item to its own
  resolved list; the menu's "Add to" list still overrides for the whole section.
- Accessibility label appends "adds to <list>".

---

## 2. Template matches

### 2a. Candidate builder (new `Services/AITemplateCandidatesBuilder.swift`)

`@MainActor static func build(for trip: Trip, targetUser: User?) -> [TemplateCandidate]`
fetches `PackingList` where `template == true` from `trip.modelContext`.

**Eligible** when all of these hold:

- `items` is non-empty.
- No trip list has `appliedFromTemplate?.uuid == template.uuid`.
- No trip list's `matchKey(name)` equals `matchKey(template.name)`.
- `template.user == nil`, or `targetUser == nil`, or `template.user == targetUser` (by
  `uuid`). Applying an owned template assigns its items to the owner, so another packer's
  template would land on the wrong person.
- Not already offered in this conversation (added or dismissed; see 2e). The view model
  filters this after `build`.

**Signals.** A template is a candidate only with at least one. Each signal carries a short
human string the model can quote:

| Signal | Rule | Strength | Example string |
| --- | --- | --- | --- |
| Past use | Applied to another trip (`appliedToLists[].trip`, excluding this trip) whose `AIPastTripsBuilder` similarity to this trip is ≥ 5 | 3 | `used on "Maui 2025", a similar trip` |
| Name match | A significant token of `matchKey(template.name)` appears as a token in `matchKey` of the trip name or of any non-Default list name | 2 | `name matches the trip name` / `name matches list "Beach"` |
| Item overlap | Of the template's item `matchKey`s, ≥ 40% and ≥ 4 are already among the recipient's trip items | 1 | `9 of 14 items already on this trip` |

- *Significant token:* ≥ 3 characters and not in a stoplist (`trip`, `list`, `packing`,
  `pack`, `travel`, `stuff`, `my`, `the`, `and`, `for`, `weekend`, `week`, `day`, `essentials`,
  `basics`, `general`, `misc`, `things`). Tokenize the `matchKey` output on spaces, and apply
  the plural trim per token.
- *Recipient* = `template.user ?? targetUser`. With no recipient, use all trip items.
- `AIPastTripsBuilder.similarity` becomes `internal` (it's `private` today) so the builder
  can reuse it, along with the threshold constant `similarTripScore = 5`.

**Ranking and caps.** Sort by total strength, then by most recent past use, then by name.
Keep 5. Each candidate sends ≤ 25 item names in `sortOrder`.

```swift
struct AITemplateCandidate: Encodable {
    let id: String        // template uuid
    let name: String
    let kind: String      // "packing" | "tasks"
    let isDayOf: Bool
    let itemCount: Int
    let items: [String]   // ≤ 25
    let signals: [String]
}
```

`AITripContext` gains `templateCandidates: [AITemplateCandidate]`, empty when there are
none. The request is rebuilt on every send, so a template applied by hand mid-chat drops out.

### 2b. Wire: response

`AIAssistantResponse` gains `template: AITemplateMatch?`:

```swift
struct AITemplateMatch: Codable {
    let id: String
    /// One short line, e.g. "You used it on Maui, another warm beach trip"
    let reason: String
}
```

In `SUGGESTION_SCHEMA` this is an optional object with `id` and `reason`, both required
inside it, `additionalProperties: false`, and left out of the top-level `required`. The
Worker passes it through as `template`. The Worker's response type and README contract are
updated.

### 2c. Prompt

This block is added to `currentState` (not the cached context) only when there are candidates.
Candidates change mid-chat (applied, offered, item overlap), so in the cached prefix they would
break the cache:

```
Templates they could add (each has a reason it may fit):
- <id> · Beach Weekend (packing, 14 items; used on "Maui 2025", a similar trip; name matches list "Beach"): Swimsuit, Sunscreen, …
```

Instructions:

- You may suggest at most one of these templates in "template", and only when you're highly
  confident it fits this trip's purpose. Usually suggest none. Never suggest a template
  that isn't listed.
- "reason" is one short sentence, specific to this trip, and may quote the listed reason.
- When you suggest a template, don't also suggest items it contains, and mention it briefly in
  "message" ("Your Beach Weekend template looks like a fit").
- Item rules are unchanged; a template doesn't count toward the 3–10 item guidance.
- If the user asks whether any template fits and none clearly does, say so plainly and
  leave out "template".

### 2d. Client validation

On receipt, keep `template` only if its `id` matches a candidate sent in *this* request. If
not, drop it silently and leave the message unchanged. (Pre-filtering means the model can
only name a qualified template, so this check just guards against a bad id.) The reply's
item suggestions are not filtered further for template overlap; the prompt handles that,
and items the template adds later show as added through `alreadyHas`.

### 2e. Persistence (`AIAssistantViewModel.ChatEntry`)

```swift
var template: TemplateOffer?

struct TemplateOffer: Codable {
    let templateID: UUID
    let name: String          // snapshot, for display if the template is renamed or deleted
    let reason: String
    var state: State          // .pending / .added(newItems: Int) / .dismissed
}
```

- *Offered in this conversation* = the template IDs of all entries' `template`, in any state.
  These are excluded from candidates (2a), which gives once-per-template-per-chat. New Chat
  clears it along with everything else.
- A pending offer whose template was deleted, or since applied by hand, renders as
  unavailable: the row is dimmed with no actions, and the caption is "No longer available"
  or "Already on this trip".

### 2f. Applying (`AIAssistantViewModel.addTemplate(from entryID:)`)

1. Resolve the template by `uuid` and re-check eligibility (not applied, not the same name).
2. `PackingList.copy(template, for: trip, with: targetUser)`. This uses the existing owner
   rule and `countAsDays` scaling, and sets `appliedFromTemplate`.
3. Remove the copied items whose `matchKey` is in the recipient's existing trip item keys.
   Remove them before inserting, so nothing flashes.
4. If nothing is left, don't add a list; set the state to `.added(newItems: 0)`.
5. Otherwise insert the list and call `trip.addList(_:)` (day-of lists stay last), then set
   `.added(newItems: count)`.
6. `save()`.

The template's own items are never modified.

### 2g. UI (new `Views/AI/AITemplateOfferRow.swift`)

This is a compact row, styled like a suggestion row and in its own rounded
`secondarySystemBackground` container, placed above the category sections in the reply:

```
[glyph] Beach Weekend                          (x) (+)
        Template · You used it on Maui, another warm beach trip
```

- Leading tile: the list glyph, through the same tile styling as suggestion rows. Use the
  `ListKind.glyph(isDayOf:)` symbol; a plain packing template uses a template symbol (pick
  one from the asset catalog / SF Symbols, e.g. `list.bullet.rectangle`). **Needs design
  sign-off.**
- Title: the template name. Caption: "Template · <reason>", with the item count as a trailing
  secondary "14 items" if space allows.
- Trailing `xmark` (dismiss) and `plus.circle` (add) buttons, each with a hit target of at
  least 44pt.
- Context menu: "Add List" and "Not Now".
- Added state: the leading tile shows a checkmark, the buttons are replaced by
  `checkmark.circle.fill`, and the caption reads "Added · 9 new items" (or "Already covered"
  when 0).
- A dismissed offer is removed from the reply with `.packingSpring`.
- Accessibility: one element, labeled "Beach Weekend template, <reason>", with actions Add
  List and Not Now.

### 2h. Starter prompt

In the trip empty state (`AIAssistantSheet.emptyState`), add a third starter, "Do any of my
templates fit?", when `AITemplateCandidatesBuilder.build(for:targetUser:)` is non-empty.
It's computed on appear and when the packer changes.

---

## 3. Edge cases

- **Trip has only Default.** No caption; everything packing routes to Default.
- **Model names a day-of packing list for a non-day-of item.** Accepted (kinds agree). The
  prompt is the only guard, and the caption makes it visible before tapping.
- **Two lists with the same name.** Ids disambiguate them, and the caption shows the name. In
  practice this is acceptable.
- **Packer switched mid-chat.** Routing ids are list-level and still valid. A template offer
  made for packer A may be owned by A; if the selected packer is now B, re-checking
  eligibility at apply time (owner rule) makes it unavailable.
- **Saved chat reopened after lists changed.** Stale `listId` falls back; stale template
  shows as unavailable.
- **Template applied by hand while an offer is pending.** It shows as "Already on this trip".
- **Overlap signal with `countAsDays` templates.** Counts are irrelevant; only names are
  compared.
- **Worker gets old-shape request during development.** The prompt builder uses `lists` when
  present and falls back to `listNames`/`existingItems`. Remove the fallback once the app
  ships with the new shape (the app is unreleased).

## 4. Prompt layout and cost

The Worker already caches the prompt (`Workers/src/anthropic.ts`), in this order:

1. Mode instructions: cached and identical for every user. Routing and template rules go
   here; they are static text.
2. Trip context (facts, weather, ≤ 3 past trips): cached and fixed for the chat session. The
   app snapshots past trips on the first send (`AIAssistantViewModel.pastTripsSnapshot`).
3. History: a cache breakpoint on the latest user turn.
4. `currentState`, a mid-conversation system message, uncached: the per-list items (§1a),
   `otherPackersItems`, and template candidates (§2c).

Rules for this feature:

- Nothing that changes when an item is added, a template is applied, or an offer is made may
  go into blocks 1–3.
- Template candidates stay capped at 5 × 25 items, since they're paid at full input price on
  every send.
- Check the Worker's `usage` log line: after the first send in a chat, `cacheRead` should be
  most of `in`.

## 5. Out of scope

- The model creating new lists.
- Suggesting more than one template per reply, or templates in template mode.
- A proactive template offer before any message (the starter prompt covers discovery).
- Undo for applied templates.
- Routing in the manual add flow (`PackingEditor`).

## 6. Files

| File | Change |
| --- | --- |
| `Services/AIAssistantService.swift` | `AITripList`, `AITemplateCandidate`, `AITemplateMatch`; `AITripContext` fields; `AISuggestedItem.listId`; `AIAssistantResponse.template` |
| `Services/AITripContextBuilder.swift` | Build `lists` per list; call the candidates builder |
| `Services/AITemplateCandidatesBuilder.swift` | New: eligibility, signals, ranking |
| `Services/AIPastTripsBuilder.swift` | Expose `similarity` + `similarTripScore` |
| `ViewModels/AIAssistantViewModel.swift` | Routing resolver, `TemplateOffer` on `ChatEntry`, validation, `addTemplate`, `dismissTemplate`, offered-ID exclusion |
| `Views/AI/AISuggestedItemList.swift` | Destination caption, per-item routing in Add all |
| `Views/AI/AITemplateOfferRow.swift` | New compact row |
| `Views/AI/AIAssistantSheet.swift` | Render the offer row; template starter prompt |
| `Workers/src/types.ts`, `prompt.ts`, `index.ts`, `README.md` | Request/response shape, lists + templates blocks, schema, contract |
| `CLAUDE.md` | AI Assistant section: routing + template offers |

## 7. Test plan (manual)

1. Trip with Default, Beach (packing), Toiletries, and a day-of tasks list. Ask "What am I
   missing?". Beach gear is captioned Beach, toiletries Toiletries, "Charge phone" the
   day-of list. Tap each and confirm where it lands.
2. Long-press "Add to" a different list; it overrides the caption.
3. Delete Beach and reopen the saved chat. The old Beach suggestions now caption Default.
4. A template applied to a past trip at the same destination, not on this trip: the
   starter appears; tapping it returns the offer row with a reason.
5. Add List: the list appears before the day-of lists, duplicates are skipped, and the count
   matches the caption. Send again; that template is never re-offered.
6. Not Now: the row hides. Send again; it's not re-offered. New Chat: it's eligible again.
7. A template with no signal (a vague name, never used, little overlap) is never offered, and
   its starter is hidden when it's the only template.
8. Multiple packers on, packer B selected: packer A's owned template is never offered.
9. Ask "Do any of my templates fit?" when candidates exist but none clearly fits. The reply
   says so, and no row appears.
10. Template mode chat: no captions, no offers, unchanged behavior.
