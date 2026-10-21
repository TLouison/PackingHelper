# Trip Cover Photos — Spec

Let users replace the map background of a trip with a photo, either from their
photo library or picked from Unsplash search results.

## Summary of decisions

| Topic | Decision |
| --- | --- |
| Sources | Photo library (free) + Unsplash search (Plus only) |
| Surfaces | `TripListRowView` card background and `TripDetailHeroView` background. Map is used when no photo is set. |
| Attribution | Unsplash credit is a small caption below the last card on the trip detail page (plus photographer names in the picker grid). None on the hero or list card |
| Default | New trips get the map, as today. Photos are opt-in only. |
| Entry point | New **Cover Photo** section in `TripEditView` (covers both new-trip creation and the trip settings sheet), placed right after **Trip Name** |
| Commit model | Staged in edit state. Applied on Save, discarded on Cancel |
| Framing | Focal point picker shown after **every** pick (library and Unsplash) |
| Unsplash API | Proxied through the existing `PackingHelperWorkers` Cloudflare Worker. The access key never ships in the app |
| Unsplash storage | Hotlinked (compliant with Unsplash guidelines) plus an app-side disk cache |
| Library storage | Downscaled bytes in SwiftData (`.externalStorage`) |
| Plus lapse | Existing Unsplash photos are kept (grandfathered). Only new Unsplash selections are locked |
| Destination change | Photo is kept as-is. No prompt and no auto-clear |
| Rollout | Library ships right away. Unsplash sits behind a feature flag until Unsplash approves the production key |

---

## 1. Data model

### New `@Model TripCoverPhoto`

`Models/TripCoverPhoto.swift`

```swift
enum CoverPhotoSource: String, Codable { case library, unsplash }

@Model
final class TripCoverPhoto {
    var source: CoverPhotoSource = CoverPhotoSource.library

    // Focal point in unit coordinates (0...1), default center.
    var focalX: Double = 0.5
    var focalY: Double = 0.5
    // Extra zoom on top of aspect-fill, 1...3.
    var zoom: Double = 1.0

    // Library only
    @Attribute(.externalStorage) var imageData: Data?

    // Unsplash only
    var unsplashId: String?
    var unsplashRawURL: String?        // urls.raw; sized via imgix params at load time
    var unsplashHTMLLink: String?      // links.html (photo page)
    var photographerName: String?
    var photographerUsername: String?
    var photographerProfileURL: String? // user.links.html
    var colorHex: String?              // dominant color
    var blurHash: String?

    var trip: Trip?
    var createdDate: Date = Date.now
}
```

### `Trip` changes

```swift
@Relationship(deleteRule: .cascade, inverse: \TripCoverPhoto.trip) var coverPhoto: TripCoverPhoto?
```

- Optional and additive, so SwiftData lightweight migration handles it. No migration code needed.
- Add `TripCoverPhoto.self` to every `ModelContainer(for:)` call: `PackingHelperApp.swift`, `PreviewContainer.swift`, `SampleData.swift`.
- Replacing a photo: delete the old `TripCoverPhoto` and insert the new one (no in-place mutation across sources).
- `TripEditView` calls `trip.applyCoverPhoto(draft, in:)` on save (`Trip.create_or_update` is unused by the edit flow, so it's left alone).

## 2. Rendering

### Shared component: `CoverPhotoImageView`

`CoverPhoto/CoverPhotoImageView.swift`. `TripListRowView` and `TripDetailHeroView` draw it as a `.background` sized to the card/hero, and skip their skeleton+Map branch when a photo is set.

- If `trip.coverPhoto == nil`, render the existing map behavior unchanged (skeleton, then `Map`; non-interactive in the row, as today in the hero).
- If a photo is set:
  - Render `Image` with `.resizable().scaledToFill()`, cropped around the focal point (offset the image so the focal point stays as close to the frame center as the overflow allows).
  - The hero photo is **static**: no tap, no full-screen viewer, no toggle back to the map.
  - Clip to `defaultCornerRadius` like the map does.
- **Placeholder while loading / on cache miss:**
  - Unsplash: a decoded BlurHash (small 32×32 decode, scaled up) over a `colorHex` fill, then cross-fade the real image in.
  - Library: decode from `imageData` off the main thread. Show the systemGray5 skeleton briefly.
  - If the Unsplash image fails to load and isn't cached, keep the BlurHash/color. Do **not** fall back to the map.
- **Legibility:** no extra scrim. The existing `roundedBox()`/`shaded()` overlays are enough.

### Attribution (Unsplash only)

- **Detail page — photo credit caption:** `TripDetailPhotoCreditView`, appended as the **last** item in `TripDetailView`'s `LazyVStack` (after `TripDetailInfoView`). Not a card: a small centered `.caption2` secondary-colored line, "Photo by {Name} on Unsplash", with only the two links underlined. "{Name}" opens `photographerProfileURL` and "Unsplash" opens `https://unsplash.com`. Both get `?utm_source=packing_helper&utm_medium=referral`. Rendered only when `trip.coverPhoto?.source == .unsplash`.
- **Hero:** no attribution overlay. The hero photo stays clean.
- **Picker grid:** photographer name on each result.
- **Not** shown on the trip list card.
- `TripEditView` shows no attribution.

### Image loading/cache: `CoverPhotoImageLoader`

`Utilities/CoverPhotoImageLoader.swift`. A small actor with no third-party dependency.

- Memory: `NSCache<NSString, UIImage>` of decoded images.
- Disk: `Caches/CoverPhotos/{unsplashId}_{width}.jpg`.
- Request URL: `unsplashRawURL` + `&w={pixelWidth}&q=80&fm=jpg&fit=max`. `pixelWidth` = view width × screen scale, bucketed (e.g. 400/800/1200/1600) so the list and hero share cache entries where possible.
- De-duplicate in-flight requests per key.
- Library images also go through the loader (key = `persistentModelID` + data hash) to get the memory cache and off-main decode.
- No explicit eviction for removed photos. The Caches directory is purgeable by the OS.

## 3. Edit flow (`TripEditView`)

### Cover Photo section

Placed after `nameSection`. Built with the existing `formSection("Cover Photo")` helper.

- **Preview:** a small thumbnail at card aspect ratio (90×132) showing the staged photo cropped at its focal point. With no photo, show a "Map" placeholder state (icon + "Uses destination map").
- **Menu** (single button, e.g. "Choose Photo" / "Change Photo"):
  - **Choose from Library** → `PhotosPicker` (`matching: .images`). No photo-library permission prompt is needed.
  - **Search Unsplash** with a PLUS badge. Hidden when `FeatureFlags.shared.showingUnsplashPhotos` is false.
    - Plus active (`PurchaseManager.isPlusActive`): open the Unsplash picker sheet.
    - Not Plus: present `PlusPaywallView`.
  - **Adjust Focus** (only when a photo is staged) → focal point screen.
  - **Remove Photo** (destructive, only when a photo is staged) → staged back to the map.

### Staging

- `@State private var coverPhotoDraft: CoverPhotoDraft?` plus a flag for "removed".
- `CoverPhotoDraft` is a plain struct mirroring `TripCoverPhoto` fields, plus a `pendingUnsplashDownloadLocation` (see §5).
- Seeded from `trip.coverPhoto` when editing.
- **On Save:** apply to `Trip` (create/replace/delete the `TripCoverPhoto`). If the draft is a *newly picked* Unsplash photo, fire the download-tracking ping (fire-and-forget, non-blocking).
- **On Cancel:** discard. No ping fires.
- Changing destination does not affect the staged photo.

### Library pick processing

Done off the main thread after `PhotosPicker` returns:

1. Load `Data` via `loadTransferable(type: Data.self)`.
2. Downscale so the long edge is at most **2048px** (`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform` so orientation is baked in).
3. Re-encode as JPEG at quality 0.8 **without metadata**, which strips EXIF and GPS.
4. Go to the focal point screen.

Show a progress indicator in the preview while processing. On failure, show an inline error ("Couldn't load that photo") and leave the previous draft in place.

### Focal point screen

`CoverPhotoFocusView`. Shown after **every** pick (library and Unsplash) and from **Adjust Focus**.

- **Fixed frames, moving photo** (like iOS wallpaper cropping). A 480pt-tall editor shows two fixed outlines centered on top of each other: **Trip Page** (white, solid, ~0.9 aspect) and **Card** (yellow, dashed, 300×440 aspect). Everything outside them is dimmed. The photo sits underneath. Drag pans it and pinch zooms it (1×–3×, around the frame center). No separate preview views.
- At 1× each frame is the largest crop of its shape that fits the photo, so the frames match how each surface aspect-fills. The focus (unit `(x, y)` of the photo under the frames' center) and `zoom` are stored on `TripCoverPhoto`.
- The photo is clamped so it always covers both frames. Because the real surfaces clamp individually, the editor is a close approximation, not pixel-exact (the narrower card can't be pushed quite as far sideways as it could on its own).
- A "1.0×" readout and a **Reset** button (center + 1×) sit under the editor. VoiceOver: swipe up/down adjusts zoom by 0.25×, plus a "Reset framing" action.
- The image loader asks for proportionally more pixels when zoomed (width buckets go up to 2400px; library photos top out at their stored 2048px).
- Default is center (0.5, 0.5). **Done** accepts it, **Cancel** discards the pick (Adjust Focus Cancel keeps the prior focus).

## 4. Unsplash picker (`UnsplashPickerView`)

Presented as a sheet from `TripEditView` with `NavigationStack` and `.searchable`.

- **Initial query:** the destination name (`TripLocation.name`, the city portion if it's parseable). Results load immediately. The user can edit the query, and submitting runs a new search (page 1). Empty query → empty state prompt.
- **Grid:** 2 columns at landscape aspect. Each cell shows the `small` URL thumbnail (BlurHash/color placeholder) and the photographer name.
- **Paging:** 12 results per page, `orientation=landscape`, `content_filter=high`. A **Load More** button at the end of the grid; it's hidden when `page >= totalPages`. No infinite scroll.
- **Selection:** tapping a cell opens the focal point screen. Done returns the draft to `TripEditView` and dismisses the picker.
- **States:** loading (skeleton cells), empty results ("No photos for '{q}'"), error with Retry. 401 `not_subscribed` → refresh entitlements (`PurchaseManager.refresh()`) and show the paywall. 429 → "Too many searches, try again shortly."

## 5. Worker (`PackingHelperWorkers`)

New routes alongside `/v1/assistant/message`. Refactor `index.ts` into a small router. Keep the Swift DTOs (new `Services/UnsplashService.swift`) in sync with the README contract.

New secret: `UNSPLASH_ACCESS_KEY` (`wrangler secret put`). Requests to Unsplash use `Authorization: Client-ID …` and `Accept-Version: v1`.

### `POST /v1/photos/search`

Request:

```json
{ "rcAppUserId": "…", "query": "Lisbon", "page": 1 }
```

- Validate: query is non-empty, trimmed, max 100 chars, and `page` is between 1 and 50.
- Auth: `verifySubscriber(env, rcAppUserId)`. It already caches positives in KV for 10 min (`ENT_CACHE_TTL = 600`). Reuse it as-is.
- Cache: KV key `unsplash:search:v1:{normalizedQuery}:{page}`, where normalized means lowercased, trimmed, with whitespace collapsed. TTL **24h**. Serve from cache before calling Unsplash.
- Upstream: `GET https://api.unsplash.com/search/photos?query=…&page=…&per_page=12&orientation=landscape&content_filter=high`.
- Response: trimmed down to only what the app needs:

```json
{
  "page": 1,
  "totalPages": 34,
  "results": [
    {
      "id": "abc123",
      "width": 6000, "height": 4000,
      "color": "#a3b1c2",
      "blurHash": "LKO2?U%2Tw=w]~RBVZRi};RPxuwH",
      "urls": { "raw": "https://images.unsplash.com/…", "small": "https://images.unsplash.com/…" },
      "htmlLink": "https://unsplash.com/photos/abc123",
      "downloadLocation": "https://api.unsplash.com/photos/abc123/download?ixid=…",
      "photographer": { "name": "Jane Doe", "username": "janedoe", "profileURL": "https://unsplash.com/@janedoe" }
    }
  ]
}
```

### `POST /v1/photos/download`

Request: `{ "rcAppUserId": "…", "downloadLocation": "https://api.unsplash.com/photos/…/download?ixid=…" }`

- Validate that `downloadLocation` host is `api.unsplash.com` and the path matches `/photos/{id}/download` (prevents SSRF and open proxying).
- Auth: `verifySubscriber`.
- Calls the URL with the Client-ID header. Returns `204`. This is required by the Unsplash guidelines whenever a user selects a photo.

### Errors

Same shape as the existing contract (`{ error, message }`):

| Status | code | Meaning |
| --- | --- | --- |
| 400 | `bad_request` | Invalid body/query/downloadLocation |
| 401 | `not_subscribed` | No active Plus entitlement |
| 429 | `rate_limited` | Unsplash returned 403/429 (hourly limit exhausted) |
| 502 | `upstream_error` | Other Unsplash failure |

No per-user daily search cap for now. The 24h KV cache is the main mitigation.

## 6. Feature flag

- Add `FeatureFlags.showingUnsplashPhotos` (UserDefaults key `featureFlag_showingUnsplashPhotos`), with a toggle in `DeveloperMenu`.
- When off: the **Search Unsplash** menu item is hidden. Library photos and the rendering of existing Unsplash photos are unaffected.
- Remove the flag once Unsplash approves the production key (the demo key is 50 req/hr; production is 5,000 req/hr). The approval application needs screenshots of the picker attribution and the detail page photo credit caption.

## 7. Files

All new app code lives in one folder, `PackingHelper/CoverPhoto/`, so it can be added to the target in one drag:
- `TripCoverPhoto.swift`: model, `CoverPhotoDraft`, `CoverPhotoRepresentable`, `Trip.applyCoverPhoto(_:in:)`
- `UnsplashService.swift`: DTOs, `search(query:page:)`, `trackDownload(_:)`, UTM helper
- `CoverPhotoImageLoader.swift`: memory + disk cache, bucketed widths
- `CoverPhotoImageView.swift`: focal-point aspect-fill rendering with BlurHash/color placeholder (used as `.background` on the card and hero instead of a separate `TripBackgroundView`)
- `BlurHash.swift`: decoder
- `CoverPhotoProcessing.swift`: downscale + strip metadata
- `CoverPhotoSection.swift`, `CoverPhotoFocusView.swift`, `UnsplashPickerView.swift`
- `TripDetailPhotoCreditView.swift`

Worker: `src/unsplash.ts`, router + photo routes in `src/index.ts`, `Env.UNSPLASH_ACCESS_KEY` and photo DTOs in `types.ts`, README contract section.

Modified:
- `Trip.swift` (relationship)
- `AIAssistantService.swift` (Worker base URL moved into a shared `WorkerConfig`)
- `TripListRowView.swift`, `TripDetailHeroView.swift` (cover photo background; map hidden when a photo is set)
- `TripDetailView.swift` (photo credit caption at the bottom)
- `TripEditView.swift` (section + staging + save + download ping)
- `FeatureFlags.swift`, `DeveloperMenu.swift`
- `PackingHelperApp.swift`, `PreviewContainer.swift`, `SampleData.swift` (container models)

## 8. Out of scope

- Map access when a photo is set (no toggle, no map elsewhere)
- Auto-selecting photos for new trips
- Per-user Unsplash search caps
- Attribution on list cards
- Multiple photos per trip / galleries
- iCloud sync considerations beyond what SwiftData already does

## 9. Test plan (manual, user-run)

1. New trip → pick a library photo → adjust focus → Save. The list card and hero both show the photo cropped at the focus point.
2. Edit the trip → Remove Photo → Cancel. The photo is still there. Remove → Save → map is back.
3. Pick a large HEIC with GPS. The stored data is ≤2048px JPEG with no GPS metadata.
4. Free user → Search Unsplash → paywall appears.
5. Plus user → the picker prefills the destination. Load More appends 12; the button hides on the last page.
6. Pick an Unsplash photo → Cancel the edit. No download ping (check Worker logs). Pick → Save → ping is logged.
7. Airplane mode after viewing: the Unsplash photo renders from the disk cache. On a cache miss, the BlurHash shows, not the map.
8. Unsplash trip: photo credit caption appears below the last card on the detail page and its links open the photographer profile and Unsplash with UTM params. Library-photo and map trips show no credit caption.
9. Simulate a lapsed Plus. The existing Unsplash photo still renders, and Search Unsplash shows the paywall.
10. Change the destination. The photo is unchanged.
11. Flag off: Search Unsplash is hidden and existing Unsplash photos still render.
12. Worker: the same query twice gives a second response from KV. A bad `downloadLocation` host returns 400.
