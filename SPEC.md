# Save Trip Items Back to Templates — Spec

When a user adds items to a trip list that was applied from a template, let
them persist those new items back to the source template so future trips get
them automatically. The same review also saves lists made on the trip as new
templates.

Paths below are relative to `PackingHelper/` and refer to files and symbols,
not line numbers.

## Summary of decisions

| Topic | Decision |
| --- | --- |
| Direction | Trip → template, **new items only**. Removals and edits (rename, count) never flow back |
| Eligible lists | Only trip lists with `appliedFromTemplate != nil`. The Default list, lists made on the trip, and AI-only lists are excluded from the item review (lists made on the trip can instead be saved as new templates) |
| Matching | Normalized name (trimmed, case-insensitive, collapsed whitespace). No lineage/source-ID tracking |
| Count written to template | Always `1` (templates store base counts; `countAsDays` rescales at apply). New templates made from a trip list keep each item's count |
| Propagation | None. Other trips that applied the same template are untouched (applied lists stay snapshots) |
| Triggers | End-of-trip only: (1) review card in trip detail, (2) past trips cards on the Trips tab, (3) Templates tab "Items to Review" sheet. There is no per-row or per-list trigger while a trip is in progress |
| Review sheet | Checklist, **nothing pre-checked**, "Select All Items" per page. **Paged, one packer per screen** |
| Review availability | Trip status `.complete` only. Dismissal persisted on `Trip.templateReviewDismissed` |
| Template ownership | Templates are owned by a packer via `PackingList.user` (used for templates only) |
| Packer scoping | Only items assigned to the template's owner (or unassigned) are candidates. Other packers' items never go to it |
| Owner on create | Picker required when 2+ packers; the first packer by `created` otherwise |
| Owner migration | Existing ownerless templates go to the first packer (by `created`), once |
| Apply | An owned template's copied items are assigned to the owner (owner beats the apply-sheet packer picker) |
| Duplicates | Same normalized name within one list's eligible items collapses to one candidate |
| Pricing | Free |

---

## 1. Definitions

**Template list** — a trip `PackingList` where `template == false` and
`appliedFromTemplate != nil`. If the source template was deleted, the
relationship is nullified and the list is no longer eligible.

**Template owner** — `appliedFromTemplate.user`. `nil` only if the owning packer
was deleted (`User.delete` nullifies it).

**Eligible item** — an item for which `PackingList.isTemplateEligible(_:)` is
true: the template has no owner, the item has no packer, or the item's packer is
the template's owner. Items assigned to any other packer are never eligible, even
if that packer has a template with the same name. Writes always go through the
list's `appliedFromTemplate` relationship, never a name lookup, so same-named
templates can't be confused.

**Candidate item** — an eligible item whose normalized name is non-empty and does
not match any item name in `appliedFromTemplate.items`.

**Candidate group** (`TemplateCandidate`) — candidate items in one list sharing a
normalized name. The UI treats a group as one candidate (one review row; saving
it adds one template item).

**New-template candidate** — `PackingList.isNewTemplateCandidate`: a trip list
that isn't a template, wasn't applied from one, isn't the Default list, and has
items.

**Review packer** — the packer a candidate is reviewed under = the template's
owner. Ownerless templates are reviewed on a trailing "Shared Templates" page.

Name normalization is `String.itemMatchKey` (`Models/PackingList.swift`):
lowercased, split on whitespace, rejoined with single spaces.

Candidates are computed live — no stored flag. Adding a template item named
"Sunscreen" from the Templates tab immediately removes matching trip items from
the review, and deleting it from the template brings them back. Packed, unpacked,
or assigned to any packer, an item is eligible under the rule above.

## 2. Model changes

### 2a. Template ownership (`PackingList.user`)

Templates are owned by a packer through `PackingList.user`. Trip lists keep their
users on items; a legacy `user` on a trip list is ignored for review.

- `PackingList.save(...)` takes `owner: User?` and sets `user` for templates.
- **Template create/edit (`Views/Model Views/PackingList/PackingListEdit/PackingListEditView.swift`):**
  an inline `UserPickerView` (`allowAll: false`) is shown when 2+ packers exist.
  Required — Save is disabled until chosen. The owner starts as the list's
  current owner or the first packer by `created`. With one packer, the picker is
  hidden and the sole packer is assigned.
- **Migration:** one-time, gated by `@AppStorage("hasAssignedTemplateOwners")`,
  run alongside the other launch migrations in `PackingHelperApp.swift`
  (`assignTemplateOwners`). Every `template == true` list with `user == nil` goes
  to the first packer by `created`. No-op (flag stays false) if no packers exist
  yet; retried next launch.
- **Apply:** `PackingList.copy(_:for:with:)` assigns items to the template's owner
  when it has one, ignoring the passed user. The passed user only applies to
  ownerless templates. The apply sheet
  (`Views/Model Views/PackingList/PackingListEdit/PackingListApplyDefaultView.swift`)
  explains this under its packer picker and shows each template's owner pill when
  `FeatureFlags.showingMultiplePackers` is on. It lists all templates regardless
  of owner.
- `UserGridView` shows a template list count (`templateListCount`).

### `PackingList` (`Models/PackingList.swift`, no schema change)

```swift
extension PackingList {
    /// Normalized names of this list's items.
    var itemMatchKeys: Set<String>

    /// Whether an item may be saved back (owner's or unassigned items).
    func isTemplateEligible(_ item: Item) -> Bool

    /// Eligible items not in the source template, grouped by match key.
    /// Empty when the list isn't a trip list applied from a template.
    var templateCandidates: [TemplateCandidate]

    /// Trip list that could become a new template.
    var isNewTemplateCandidate: Bool

    static func templateNameExists(_ name: String, in templates: [PackingList]) -> Bool

    /// Adds one item per candidate to `appliedFromTemplate`.
    func saveToTemplate(_ candidates: [TemplateCandidate], in context: ModelContext)

    /// Copies this list's items into a new owned template and links the list to it.
    func saveAsNewTemplate(named name: String, owner: User?, in context: ModelContext) -> PackingList
}

struct TemplateCandidate: Identifiable {
    let key: String          // itemMatchKey
    let items: [Item]        // all trip items in the group (>=1), oldest first
    var id: String { key }
    var displayItem: Item    // oldest member; supplies name/category
}
```

`saveToTemplate` creates template items with:

| Field | Value |
| --- | --- |
| `name` | `displayItem.name` (original casing, trimmed) |
| `category` | copied from `displayItem` (no ML re-run) |
| `count` | `1` |
| `isPacked` | `false` |
| `user` | none (templates are generic; the packer comes from the template's owner at apply) |
| `sortOrder` | appended after the template's current max `sortOrder` |
| `list` | the template |

Membership is re-checked inside `saveToTemplate` right before inserting (guards
against double-taps and stale review sheets). Items are inserted into the
context and wired with `templateItem.list = source`.

`saveAsNewTemplate` copies the list's `kind` and `isDayOf`, names the template
(trimmed), assigns the owner, copies item name, category, and count in custom
order (unpacked, no packer), and sets `appliedFromTemplate` on the trip list so
later additions are reviewed like any template's. The review sheet owns the
policy: the owner is the first packer by `created`, and a name that matches an
existing template is allowed with a warning.

### `Trip` (`Models/Trip.swift`)

```swift
/// Set when the user saves from or dismisses the post-trip template review.
var templateReviewDismissed: Bool = false
```

Default value only, so lightweight migration. Computed helpers:

```swift
extension Trip {
    var listsFromTemplates: [PackingList]
    /// Template lists that currently have candidates, in list order.
    var templateCandidateSections: [PackingList]
    var templateCandidateCount: Int          // total candidate groups
    /// Lists made on the trip that could be saved as new templates.
    var newTemplateCandidateLists: [PackingList]
    /// complete && !templateReviewDismissed && (candidates or new lists)
    var showsTemplateReviewCard: Bool
    var templateReviewCount: Int             // items + new lists, for badges
    var templateReviewSummary: String        // "3 new items and 1 new list"
}
```

## 3. Entry points

The review is opened from `TemplateUpdateSheet(trip:onSaved:)`; every entry point
passes `onSaved` to set `trip.templateReviewDismissed = true`. All are gated on
`Trip.showsTemplateReviewCard`.

1. **Trip detail** — `TemplateReviewCard` (in
   `Views/Model Views/PackingList/TemplateUpdate/TemplateUpdateSheet.swift`)
   is shown by `Views/Model Views/Trip/TripDetail/TripDetailPackingView.swift`.
   Copy: "This trip has *summary* to review for your templates." Buttons:
   **Review** (opens the sheet) and a close `xmark` (sets
   `templateReviewDismissed = true`).
2. **Trips tab, past trips** — `PastTripsSummaryCard` lists trips needing review
   with `TemplateReviewTripRow`; `PastTripsEntryCard` shows the count.
   `TripListScrollView` presents the sheet for the chosen trip. A row's dismiss
   sets `templateReviewDismissed`.
3. **Templates tab** — `DefaultPackingListView` presents
   `TemplateReviewTripsSheet` ("Items to Review"), one `TemplateReviewTripRow`
   per past trip. The tab badge (`ContentView`) counts completed trips where
   `showsTemplateReviewCard` is true.

Saving or skipping from the sheet sets `templateReviewDismissed = true` even if
not every candidate was saved. Cancel leaves the review available. The card
also disappears on its own once candidates and new lists reach zero.

## 4. `TemplateUpdateSheet`

(`Views/Model Views/PackingList/TemplateUpdate/TemplateUpdateSheet.swift`)

```swift
struct TemplateUpdateSheet: View {
    let trip: Trip
    var onSaved: (() -> Void)? = nil
}
```

- **Paged by packer.** `TemplateReviewPage.pages(for:)` groups
  `trip.templateCandidateSections` by template owner: owned pages ordered by
  packer `created`, a "Shared Templates" page last for ownerless templates.
  Packers with no candidates have no page. Navigation is a `NavigationStack` with
  a pushed page per index; selections live in the sheet so back-navigation keeps
  them. The title reads "1 of 3" with more than one page, else "Review Trip".
- **Update block** ("Update Your Templates", or "Update Alex's Templates" when
  `showingMultiplePackers` is on): one group per trip list, headed by its
  template name. Rows are a checkmark toggle, item name, and category. One row
  per candidate group. **All unchecked initially.** A bottom-bar "Select All
  Items" / "Deselect All Items" applies to the current page.
- **Save New Templates block** ("Save New Templates"), shown once on the last
  page: one row per `newTemplateCandidateLists` entry, with its glyph/name
  (`ListNameLabel`), item count, and an orange note when a template with that
  name already exists. A trip with only new lists gets a single page holding
  just this block.
- Toolbar: Cancel (leading). Trailing: **Next** on non-final pages; **Save** on
  the final page, or **Skip** when nothing is selected.
- Footer on the last page: "Selected items are added to their templates with a
  count of 1." / "New templates keep each item's count." / "Your other trips
  won't change."
- Nothing is written until the final save: `saveToTemplate` per list, then
  `saveAsNewTemplate` per selected list that is still a new-template candidate
  (owner = first packer by `created`), then `modelContext.save()`, a `.success`
  haptic when something was saved, `onSaved?()`, dismiss. Cancel on any page
  discards everything.
- Candidates are snapshotted on appear; save re-validates (see §2).
- With nothing to review the sheet shows "Templates Are Up to Date".

## 5. Edge cases

| Case | Behavior |
| --- | --- |
| Source template deleted | `appliedFromTemplate` is nil, so the list isn't eligible; it can show up as a new-template candidate instead |
| Template edited after apply, adds "Socks" | Trip "Socks" now matches, so it drops out of the review |
| User renames trip item to match template item | Drops out (live) |
| Packer B adds "Hat" to a list from A's template | Not a candidate. Never offered for B's same-named template |
| Unassigned item (`user == nil`) in A's template list | Eligible, reviewed on A's page |
| Owner and an unassigned item both add "Sunscreen" | One review row; saving adds one template item |
| Template owner deleted | `user` nullified, so the template is shared: any packer's items are eligible, reviewed on "Shared Templates" |
| Template's owner changed after apply | Live: eligibility follows the current owner |
| Trip lists with a legacy `user` | Ignored; ownership is only read from templates |
| The Default list | Not applied from a template and never a new-template candidate |
| Item is AI-suggested and added into a template list | Eligible like any other item |
| Trip list saved as a new template | The list is linked to it (`appliedFromTemplate`), so it stops being a new-template candidate and later additions are reviewed as items |
| New list name matches an existing template | Allowed; the row warns and saving makes a second template |
| Same template applied twice to one trip (two lists) | Each list is evaluated separately; saving one adds the item to the template, which removes it from the other live |

## 6. Out of scope

- Removing items from templates based on trip deletions.
- Syncing renames or count changes.
- Lineage tracking (`sourceItemUUID`).
- Per-item or per-list saving while a trip is in progress, and undo (undo = delete from the template in the Templates tab).
- Pushing new template items into other trips.
- Save-back from lists that weren't applied from a template (use Save as Template instead).

## 7. Files

| File | Role |
| --- | --- |
| `Models/PackingList.swift` | `itemMatchKey`, `TemplateCandidate`, `templateCandidates`, `isTemplateEligible`, `saveToTemplate`, `saveAsNewTemplate`, `templateNameExists`, `save(owner:)`, owner-wins in `copy(_:for:with:)` |
| `Models/Trip.swift` | `templateReviewDismissed`, `templateCandidateSections`, `templateCandidateCount`, `newTemplateCandidateLists`, `showsTemplateReviewCard`, `templateReviewCount`, `templateReviewSummary` |
| `../PackingHelperApp.swift` | `assignTemplateOwners` migration |
| `Views/Model Views/PackingList/PackingListEdit/PackingListEditView.swift` | Owner picker (templates, 2+ packers) |
| `Views/Model Views/PackingList/PackingListEdit/PackingListApplyDefaultView.swift` | Owner pills and owner-wins note |
| `Views/Model Views/PackingList/TemplateUpdate/TemplateUpdateSheet.swift` | `TemplateUpdateSheet`, `TemplateReviewPage`, `TemplateReviewCard` |
| `Views/Model Views/PackingList/TemplateUpdate/TemplateReviewTripRow.swift` | Per-trip review row |
| `Views/Model Views/PackingList/TemplateUpdate/TemplateReviewTripsSheet.swift` | Templates tab "Items to Review" sheet |
| `Views/Model Views/Trip/TripDetail/TripDetailPackingView.swift` | Shows `TemplateReviewCard` |
| `Views/Model Views/Trip/TripList/TripListScrollView.swift`, `PastTripsSummaryCard.swift`, `PastTripsEntryCard.swift` | Past trips entry points |
| `Views/Model Views/DefaultPackingList/DefaultPackingListView.swift`, `Views/ContentView.swift` | Templates tab sheet and badge |

## 8. Test plan (manual)

1. Apply template "Clothing" to a trip, add "Hat" to that list, and set the trip
   dates in the past. Trip detail shows the review card with "1 new item".
2. Review: nothing is checked, Select All Items works, Skip appears with no
   selection. Cancel leaves the card. Save with "Hat" checked: the card is gone
   permanently, and the template has "Hat" with count 1 and no packer.
3. Add "  hat " (extra spaces, different case) instead: it matches the template
   item and is not offered.
4. Add "Scarf" as the owner and once unassigned: one review row; saving adds one
   template item.
5. Packer B adds "Gloves" to A's "Clothing" list: absent from the review, even
   when B owns a template named "Clothing".
6. Two packers, each with their own templates applied; complete the trip. Page 1
   is A's items by template, Next goes to page 2 (B's). Back keeps checks. Cancel
   on page 2 saves nothing. Save puts each item in its owner's template.
7. Make a new list on the trip with items. The sheet shows the Save New Templates
   block on the last page. Saving creates an owned template with the same items
   and counts, and the list no longer appears as new. A name that matches an
   existing template shows the orange warning.
8. Trip with only a new list: one page with just the new templates block.
9. Dismiss with the close button: the card is gone. Trips tab past trips cards and
   the Templates tab sheet and badge stop counting the trip.
10. Delete the source template: its candidates vanish from the review.
11. Fresh install migration: ownerless templates get the first packer.
12. New template with 2 packers: Save is disabled until an owner is picked; with 1
    packer there is no picker.
13. Apply A's template while choosing B in the apply sheet: items go to A.
14. Another trip using the same template is unchanged after saving.
