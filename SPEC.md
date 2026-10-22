# Save Trip Items Back to Templates — Spec

When a user adds items to a trip section that was applied from a template, let
them persist those new items back to the source template so future trips get
them automatically.

## Summary of decisions

| Topic | Decision |
| --- | --- |
| Direction | Trip → template, **new items only**. Removals and edits (rename, count) never flow back |
| Eligible sections | Only trip sections with `appliedFromTemplate != nil`. Default list, custom, and AI-only sections are excluded |
| Matching | Normalized name (trimmed, case-insensitive, collapsed whitespace). No lineage/source-ID tracking |
| Count written to template | Always `1` (templates store base counts; `countAsDays` rescales at apply) |
| Propagation | None. Other trips that applied the same template are untouched (applied lists stay snapshots) |
| Triggers | (1) Leading swipe on a row, (2) section header context menu → "Update Template…", (3) post-trip card in trip detail |
| Indicator | Subtle "New" pill after the item name for candidate items |
| Swipe | Leading (right) swipe, **reveal-only**. Tapping the revealed button opens a confirmation alert explaining the save is permanent for future trips |
| Feedback | Pill animates out + `.success` haptic after confirming. No toast, no undo |
| Review sheet | Checklist, **nothing pre-checked**, "Select All" available. **Paged, one packer per screen** |
| Post-trip card | Trip status `.complete` only. Paged-by-packer sheet, grouped by template within a page. Dismissal persisted on `Trip` |
| Template ownership | **New:** templates are owned by a packer via the existing `PackingList.user` field (revived for templates) |
| Packer scoping | Only items assigned to the template's owner (or unassigned) are candidates. Other packers' items never go to it |
| Owner on create | Picker required when 2+ packers; auto-assigned to the sole packer otherwise |
| Owner migration | Existing ownerless templates → first packer (by `created`) |
| Apply | Owned template's copied items are assigned to the owner (owner beats the apply-sheet packer picker) |
| Duplicates | Same normalized name within one section's eligible items collapses to one candidate |
| Pricing | Free |

---

## 1. Definitions

**Template section** — a trip `PackingList` where `template == false` and
`appliedFromTemplate != nil`. If the source template was deleted, the
relationship is nullified and the section is no longer eligible.

**Template owner** — `template.user` (see §2a). `nil` only if the owning packer
was deleted (`User.delete` nullifies it).

**Eligible item** — an `Item` in a template section where
`template.user == nil || item.user == nil || item.user == template.user`.
Items assigned to any other packer are never eligible, even if that packer has a
template with the same name. Writes always go through the section's
`appliedFromTemplate` relationship, never a name lookup, so same-named templates
can't be confused.

**Candidate item** — an eligible item whose normalized name does not match any
item name in `appliedFromTemplate.items`.

**Candidate group** — candidate items in one section sharing a normalized name.
The UI treats a group as one candidate (one review row; saving any member
clears the pill on all members).

**Review packer** — the packer a candidate is reviewed under = the template's
owner. Ownerless templates are reviewed on a trailing "Shared" page.

Name normalization:

```swift
extension String {
    /// Key for "same item" comparisons between trip lists and templates.
    var itemMatchKey: String {
        lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
```

Candidates are computed live — no stored flag. Adding a template item named
"Sunscreen" from the Templates tab immediately clears the pill on matching trip
items, and deleting it from the template brings the pill back. Everything
packed, unpacked, or assigned to any packer is eligible.

## 2. Model changes

### 2a. Template ownership (`PackingList.user`)

Today templates have no owner: `PackingListEditView` / `PackingList.save` never
set `user`, and the field is commented as legacy. Pre-v2 templates may still
have it set. This spec revives it **for templates only** (trip lists still keep
users on items).

- Update the legacy comment on `PackingList.user`: "Template owner. Unused for
  trip lists (users live on items)."
- `PackingList.save(...)` gains `owner: User?`; sets `user` when
  `template == true`.
- **Template create/edit (`PackingListEditView`, template mode):** packer picker
  (`UserPickerView`, `allowAll: false`) shown when 2+ packers exist. Required —
  Save disabled until chosen; preselect the first packer by `created`. With one
  packer, the picker is hidden and the sole packer is assigned.
- **Migration:** one-time, gated by `@AppStorage("hasAssignedTemplateOwners")`,
  run alongside the existing launch migrations in `PackingHelperApp.swift`. Every
  `template == true` list with `user == nil` → first packer by `created`. No-op
  (and flag stays false) if no packers exist yet; retry next launch.
- **Templates tab:** `DefaultPackingViewListTypeSectionView` already shows the
  owner pill from `packingList.user`; the existing packer filter
  (`PackingListFilterSection`) now works for real.
- `UserGridView` "N template lists" count becomes accurate as-is.
- **Apply:** `PackingList.copy(_:for:with:)` assigns items to `list.user` when the
  template has an owner, ignoring the passed user. The passed user only applies
  to ownerless templates. The apply-sheet packer picker keeps working for those.
  Update comments at `PackingListApplyDefaultView.swift:176` and
  `TripEditView.swift:419`.
- `PackingListApplyDefaultView` still lists all templates (not filtered by
  packer). Show the owner pill on each row so it's clear whose list it is.
- Leave `UserPickerView`/`UserPickerBaseView` `list.user == user` branches
  (IMPROVEMENTS 1.9) as-is; they become meaningful again. Update 1.9's note.

### `PackingList` (extension, no schema change)

```swift
extension PackingList {
    /// Normalized names of this list's items.
    var itemMatchKeys: Set<String>

    /// Eligible template-section items (owner/unassigned only) not present in
    /// the source template, grouped by match key. Empty when the list isn't a
    /// template section.
    var templateCandidates: [TemplateCandidate]

    /// Adds one item per candidate to `appliedFromTemplate`.
    func saveToTemplate(_ candidates: [TemplateCandidate], in context: ModelContext)
}

struct TemplateCandidate: Identifiable, Hashable {
    let key: String          // itemMatchKey
    let items: [Item]        // all trip items in the group (≥1)
    var id: String { key }
    var displayItem: Item    // earliest-created member; supplies name/category/type
}
```

`saveToTemplate` creates template items with:

| Field | Value |
| --- | --- |
| `name` | `displayItem.name` (original casing, trimmed) |
| `category` | copied from `displayItem` (no ML re-run) |
| `type`, `isDayOf` | copied |
| `count` | `1` |
| `isPacked` | `false` |
| `user` | `nil` (templates are generic) |
| `sortOrder` | appended after the template's current max `sortOrder` |
| `list` | the template |

Re-check membership inside `saveToTemplate` right before inserting (guards against
double-taps and stale review sheets). Insert into context, then
`list.addItem`. Don't use `Item.copyForTemplate` (it wires `.list` to the source;
see IMPROVEMENTS 3.4).

### `Trip`

```swift
/// Set when the user saves from or dismisses the post-trip template review card.
var templateReviewDismissed: Bool = false
```

Default value only, so lightweight migration. Plus a computed helper:

```swift
extension Trip {
    /// Template sections that currently have candidates.
    var templateCandidateSections: [PackingList]
    var templateCandidateCount: Int   // total candidate groups across sections

    /// Candidate sections grouped by review packer (template owner), ordered
    /// by packer `created`; ownerless templates last under `nil` ("Shared").
    var templateCandidatesByPacker: [(packer: User?, sections: [PackingList])]
}
```

## 3. Trigger 1 — Row indicator and leading swipe

Applies to `UnifiedItemRow` wherever trip items render (`ReorderableItemsSection`,
`PackedItemsSection`, `UnifiedPackingListView`). Never in templating mode.

### Indicator

- Subtle "New" capsule (`caption2`, medium weight, secondary text on
  `.quaternary` fill) trailing the item name, before the count badge. A bare dot
  was dropped as too cryptic.
- `accessibilityLabel`: "New, not in template".
- Removed with `.transition(.scale.combined(with: .opacity))` when the item stops
  being a candidate.

### Leading swipe

- New optional parameter on `UnifiedItemRow`:
  `onAddToTemplate: (() -> Void)?`. `nil` = right-swipe does nothing (current
  clamp at `min(0, …)` stays in effect).
- When set, offset range becomes `revealOffsetLeading...` and trailing as today.
  Leading reveal ≈ +72pt, accent-colored button with
  `square.and.arrow.down.on.square` (or `plus.square.on.square`), mirroring the
  delete button's shape.
- **Reveal only.** Dragging past the reveal point rubber-bands; releasing rests
  at reveal or closes. No full-swipe commit, no full-swipe haptic.
- Tap revealed button → `closeSwipe()`, `onAddToTemplate()`. Nothing is saved yet.
- Accessibility action "Add to Template" when available (same confirmation).
- The caller passes the closure only when the item is a candidate. It presents a
  confirmation alert (owned by `SectionedPackingListView`, not the row):
  - Title: "Add to Template?"
  - Message: "\"Hat\" will be saved to your \"Clothing\" template, so future trips
    that use it will include this item. Trips that already use this template
    won't change." With 2+ packers and an owned template: "…to Alex's
    \"Clothing\" template…". If the item's count is >1, adds "It will start with
    a count of 1."
  - Buttons: **Add to Template** / Cancel.
  - Confirm → `list.saveToTemplate([candidate containing item])` with animation,
    `.success` haptic. This is rare, so the extra tap is acceptable friction.

Since `UnifiedItemRow` doesn't know about templates, the parent computes
candidacy once per section (`Set` of candidate item IDs), not per row.

## 4. Trigger 2 — Section "Update Template…"

- `PackingListSectionHeader` context menu gets
  `Label("Update Template…", systemImage: "square.and.arrow.down.on.square")`,
  shown only when `packingList.templateCandidates` is non-empty. Placed after
  "Edit List".
- Opens `TemplateUpdateSheet` scoped to that one section.

## 5. Trigger 3 — Post-trip card

- In `TripDetailPackingView`, above the packing list (and above the columns in
  the wide layout), show `TemplateReviewCard` when:
  `trip.status == .complete && !trip.templateReviewDismissed && trip.templateCandidateCount > 0`.
- Copy: "You added N items that aren't in your templates." Buttons: **Review**
  (opens `TemplateUpdateSheet` with all candidate sections) and a close `xmark`
  (sets `templateReviewDismissed = true`).
- Saving from the sheet opened via this card sets `templateReviewDismissed = true`
  even if not every candidate was saved. Cancel leaves the card visible.
- Card also disappears on its own once candidates hit zero (e.g. user saved all
  via swipe).

## 6. `TemplateUpdateSheet`

Shared by triggers 2 and 3.

```swift
struct TemplateUpdateSheet: View {
    let sections: [PackingList]          // 1 for section trigger, many for card
    var onSaved: (() -> Void)? = nil     // card uses this to set dismissed
}
```

- **Paged by packer.** Pages come from `templateCandidatesByPacker` (filtered
  to `sections`); packers with no candidates are skipped. Section trigger always
  yields one page (one template = one owner). Pager = `NavigationStack` with a
  pushed page per packer (or `TabView(.page)` — implementer's call, but
  back-navigation must keep selections).
- Page header: packer avatar (`user.pillIcon` / initial icon) + "Alex's items".
  Shared page: "Shared templates". Page counter "1 of 3" in the nav title area
  when more than one page.
- Page body: `List`, one `Section` per trip section, header = template name
  (e.g. "Clothing template"). Section order = trip section order.
- Rows: checkmark toggle + item name + category. One row per candidate group.
  **All unchecked initially.** "Select All" / "Deselect All" per page.
- Toolbar: Cancel (leading). Trailing: **Next** on non-final pages, **Add N to
  Templates** on the final page (N = total across all pages; enabled at 0 so
  the user can finish a review that saves nothing — card flow still marks
  dismissed, section flow just closes).
- Footer: "Added items start with a count of 1. Trips that already use these
  templates aren't changed."
- Nothing is written until the final save: then `saveToTemplate` per section
  across all pages, `.success` haptic, `onSaved?()`, dismiss. Cancel on any page
  discards everything.
- Candidates are snapshotted on appear; save re-validates (see §2).

## 7. Edge cases

| Case | Behavior |
| --- | --- |
| Source template deleted | `appliedFromTemplate` is nil → section not eligible, no pills/menu |
| Template edited after apply, adds "Socks" | Trip "Socks" now matches → pill clears |
| User renames trip item to match template item | Pill clears (live) |
| Packer B adds "Hat" to a section from A's template | Not a candidate: no pill, no swipe, not in review. Never offered for B's same-named template |
| Unassigned item (`user == nil`) in A's template section | Eligible, reviewed on A's page |
| Owner and an unassigned item both add "Sunscreen" | One review row; saving clears both pills |
| Template owner deleted | `user` nullified → template shared → any packer's items eligible, reviewed on "Shared" page |
| Template's owner changed after apply | Live: eligibility follows the current owner |
| Trip lists with a pre-v2 legacy `user` | Ignored; ownership only read when `template == true` |
| Template section is the default list | Not possible today (default list isn't from a template) |
| Item is AI-suggested and added into a template section | Eligible like any other item |
| Trip saved via "Save As Default" into a new template | New list isn't linked back (IMPROVEMENTS 3.4); out of scope |
| Swipe on a non-candidate | No leading reveal |
| Same template applied twice to one trip (two sections) | Each section evaluated separately; saving from one clears pills in both via live match |

## 8. Out of scope

- Removing items from templates based on trip deletions.
- Syncing renames or count changes.
- Lineage tracking (`sourceItemUUID`).
- Toast / undo (undo = delete from template in Templates tab).
- Pushing new template items into other trips.
- Save-back from non-template sections.

## 9. Files touched

| File | Change |
| --- | --- |
| `Models/PackingList.swift` | `itemMatchKeys`, `templateCandidates`, `saveToTemplate`; `user` comment; `save(owner:)`; owner-wins in `copy(_:for:with:)` |
| `Models/Trip.swift` | `templateReviewDismissed`, `templateCandidateSections`, `templateCandidateCount`, `templateCandidatesByPacker` |
| `PackingHelperApp.swift` | Template owner migration |
| `PackingList/PackingListEdit/PackingListEditView.swift` | Owner picker (template mode, 2+ packers) |
| `PackingList/PackingListEdit/PackingListApplyDefaultView.swift` | Owner pill on rows; comment fix |
| `Trip/TripEdit/TripEditView.swift` | Comment fix (`:419`) |
| `IMPROVEMENTS.md` | Update 1.9 note |
| `Utilities/` (String ext) | `itemMatchKey` |
| `Shared/ItemRowViews.swift` | "New" pill, leading reveal swipe, `onAddToTemplate` |
| `Shared/ReorderableItemsSection.swift`, `PackedItemsSection` | Compute candidate IDs, pass closure |
| `Shared/PackingListSectionHeader.swift` | "Update Template…" menu item |
| `SectionedPackingListView.swift` | Sheet presentation for section trigger |
| `Trip/TripDetail/TripDetailPackingView.swift` | `TemplateReviewCard` |
| New `PackingList/TemplateUpdate/TemplateUpdateSheet.swift`, `TemplateReviewCard.swift` | Add via Xcode for target membership |

## 10. Test plan (manual)

1. Apply template "Clothing" to trip. Add "Hat" to the section → "New" pill appears.
2. Right-swipe "Hat" → button reveals; overswipe doesn't commit; tap → confirmation
   alert explaining the save. Cancel → nothing saved, pill stays. Confirm → haptic, pill
   fades. Open template → "Hat", count 1, no packer.
3. Add "  hat " for the owner again → no pill (normalized match).
4. Add "Scarf" for owner and once unassigned → one row in "Update Template…";
   save → both pills gone.
4a. Packer B adds "Gloves" to A's "Clothing" section → no pill, no swipe, absent
   from review, even when B owns a template named "Clothing".
4b. Two packers, each with own templates applied; complete trip → card →
   page 1 = A's items by template, Next → page 2 = B's. Back keeps checks.
   Cancel on page 2 → nothing saved. Save → each item in its owner's template.
4c. Fresh install migration: ownerless templates get the first packer; owner pill
   appears in Templates tab.
4d. New template with 2 packers → Save disabled until owner picked; with 1
   packer → no picker, auto-owned.
4e. Apply A's template choosing B in the apply sheet → items assigned to A.
5. Section with no candidates → no "Update Template…" in menu.
6. Default "Packing List" section items → never a pill, no right-swipe.
7. Delete source template → pills vanish from that trip section.
8. Set trip dates in the past → card shows with count; Review → grouped sheet,
   nothing checked; save one → card gone permanently. Repeat with ✕ → gone.
9. Cancel from card's sheet → card stays.
10. Other trip using the same template → unchanged after save.
11. VoiceOver: "Not in template" announced; "Add to Template" action works.
