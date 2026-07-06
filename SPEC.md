# BingeBuddy — Build Plan & Spec

A private watch-tracker for two people (you + your wife). Tracks shows, movies, and
anime across **Want to watch / Watching / Finished**, with personal portals, a shared
"watch together" space, show-idea suggestions, an owner-only private vault, automatic
metadata + cover art, and a recommendation engine.

Platform: iOS (native SwiftUI). Sync: CloudKit. CI/CD: Codemagic.
Status: **planning** — nothing built yet. This doc is the thing we react to and revise.

---

## 1. Goals & non-goals

**Goals**
- Two separate users on two separate iPhones / iCloud accounts.
- Personal lists per user, plus a shared "Together" space.
- Send each other show ideas (a suggestion inbox).
- A private, Face ID–locked vault visible only to its owner (you).
- Auto-fetch cover art, synopsis, seasons, episodes for film/TV **and** anime.
- Episode-level progress tracking.
- Content-based recommendations from each person's taste.

**Non-goals (v1)**
- No public/social network, no other users, no accounts to manage beyond Apple ID.
- No streaming playback — this tracks what you watch elsewhere, it doesn't play it.
- No Android/web (CloudKit choice is iOS-first by design; revisit only if needed).

---

## 2. Users & spaces model

Three logical "spaces":

| Space        | Who sees it            | Where it lives (CloudKit)                     |
|--------------|------------------------|-----------------------------------------------|
| **My portal**   | You only             | Your **private** database                     |
| **Her portal**  | Her only             | Her **private** database                      |
| **Together**    | Both                 | A **shared** custom zone (CKShare)            |
| **Vault**       | You only (Face ID)   | Your **private** database, never shared       |

Key property: because the vault lives in *your* private database and is never added to a
CKShare, it **physically cannot reach her device**. The Face ID lock is a second layer on
top of that, not the only thing protecting it.

Identity = Sign in with Apple / iCloud account. No passwords for us to store.

---

## 3. Feature breakdown

### 3.1 Library & states
- An item has a state per user: `wantToWatch`, `watching`, `finished` (+ optional `dropped`).
- Personal rating (e.g. 1–5 or thumbs) and a private note.
- Episode-level progress for series/anime: current season + episode, "next up" shown on the card.
- Filtering & sorting: by type (Movie/TV/Anime), state, genre, rating, recently updated.

### 3.2 Together space
- Items you're watching as a couple, with **shared** progress ("we're on S2E4").
- **Match view:** titles that are on *both* of your Want-to-watch lists → "what to watch tonight."
- Optional: a shared note/log per title ("loved the finale").

### 3.3 Suggestions (show-idea sharing)
- "Suggest to <partner>" from any title.
- Partner gets an inbox: **Accept → my Want list**, or **Dismiss**, optional one-line message.
- Badge count on the inbox.

### 3.4 Private vault (owner-only)
- A separate section inside your profile, hidden from the UI unless unlocked.
- **Face ID / Touch ID gate** (LocalAuthentication), with passcode fallback.
- Its own lists/states, same tracking features, completely separate from everything else.
- Never appears in her app, never in Together, never in recommendations shared with her.
- Design note: implemented as a generic "private locked collection" so it's clean,
  testable, and not a special-case hack.

### 3.5 Metadata & search
- Search a title → results with poster, year, type, synopsis.
- Add to a list pulls full detail: seasons, episode counts/titles, runtime, genres, cast,
  cover art, backdrop.
- Sources:
  - **TMDB** — movies + Western/most TV. (Free API key.)
  - **AniList GraphQL** (with Jikan/MyAnimeList as fallback) — anime seasons, cours,
    episode counts, dub/sub nuance. (Free, no key for AniList; rate-limited.)
  - Router decides source by media type; results normalized into one internal model.
- Posters/backdrops cached on-device (and we store the image URL + a cached copy).

### 3.6 Recommendations
- **Content-based filtering**, on-device, per user:
  - Build a taste profile from finished/highly-rated items: weighted genres, keywords,
    studios (anime), cast/creators.
  - Pull TMDB "similar"/"recommendations" + AniList "recommendations" for seeded titles.
  - Score & rank candidates against the taste profile; drop anything already in a list.
- "For you" row per portal; optionally a "For us" row in Together (intersection of tastes).
- Vault items can optionally feed *your* private recs but never the shared ones.
- Starts simple; we can add collaborative signals later if we want.

---

## 4. Data model (CloudKit record types)

All records normalized around a shared `MediaItem` reference so the same show isn't
re-fetched per list.

- **MediaItem** (cacheable, derived from APIs)
  `id` (our id), `source` (tmdb/anilist), `sourceId`, `type` (movie/tv/anime),
  `title`, `year`, `synopsis`, `posterURL`, `backdropURL`, `genres[]`, `seasonCount`,
  `episodeCount`, `runtime`, `cast[]`, `studios[]`, `lastRefreshed`.

- **ListEntry** (one per user per item; lives in private OR shared zone)
  `mediaItemRef`, `ownerScope` (mine/hers/together/vault), `state`, `rating`, `note`,
  `currentSeason`, `currentEpisode`, `addedAt`, `updatedAt`.

- **Suggestion**
  `mediaItemRef`, `fromUser`, `toUser`, `message`, `status` (pending/accepted/dismissed),
  `createdAt`.

- **TasteProfile** (optional, can be computed on the fly)
  `userScope`, `genreWeights`, `keywordWeights`, `updatedAt`.

CloudKit specifics:
- Personal entries → user's **private DB**, default zone.
- Vault entries → user's **private DB**, in a dedicated record type, never shared.
- Together entries → a **custom zone** owned by one of you, shared to the other via
  **CKShare** (one-time accept).
- Use `NSPersistentCloudKitContainer` (Core Data + CloudKit) so we get local-first storage,
  offline use, and automatic sync — this is the least-code path that still supports sharing.

---

## 5. Architecture / tech stack

- **SwiftUI** app, iOS 17+ (gets us the newest SwiftData/Observation niceties; confirm your
  target devices' OS).
- **Core Data + CloudKit** via `NSPersistentCloudKitContainer` (private + shared scopes).
  - (Alternative: SwiftData — cleaner API but its CloudKit *sharing* story is still thin;
    Core Data+CloudKit is the safe choice for the shared zone. Noted as a decision point.)
- **LocalAuthentication** for the vault gate.
- **Networking:** async/await `URLSession`; a thin `MetadataService` with `TMDBProvider`
  and `AniListProvider` behind one protocol.
- **Image loading/caching:** lightweight (Nuke, or roll a small `URLCache`-backed loader).
- **No third-party backend** — CloudKit only. Secrets: TMDB key stored in a config not
  committed to git (see §8).

### Folder sketch
```
BingeBuddy/
  App/            // entry point, app state, routing
  Models/         // Core Data model + domain structs
  Sync/           // CloudKit container, share controller
  Services/
    Metadata/     // MediaProvider protocol, TMDBProvider, AniListProvider, Router
    Recommend/    // taste profile + scorer
    Auth/         // vault gate
  Features/
    Library/      // lists, item detail, progress
    Together/     // shared space + match view
    Suggestions/  // inbox + send
    Vault/        // locked section
    Search/       // search + add flow
    Settings/
  Resources/
```

---

## 6. Screen / navigation map

Tab bar (your app):
1. **Library** — your lists (segmented: Want / Watching / Finished), filters, "For you" row.
2. **Together** — shared lists, Match view, shared progress.
3. **Search** — find + add titles.
4. **Inbox** — suggestions from her (badge).
5. **Profile/Settings** — account, partner pairing, and the **Vault** entry (Face ID).

Her app is identical minus the vault entry (the vault simply doesn't exist in her data).

Key flows:
- **Pairing:** one of you taps "Invite partner" → CloudKit share link via Messages → she
  accepts → Together space is live. One-time.
- **Add a title:** Search → pick result → choose space + state → metadata auto-fills.
- **Track progress:** open item → bump episode / mark finished → reflected on card + recs.
- **Unlock vault:** Profile → Vault → Face ID → contents appear for the session.

---

## 7. Recommendation engine — detail

1. On finish/rate, update the user's taste vector: `+w` to the item's genres/keywords
   (weight scaled by rating).
2. Seed set = top-rated + recently finished titles.
3. For each seed, fetch provider "similar"/"recommendations" (TMDB + AniList).
4. Candidate score = cosine-ish similarity of candidate's genre/keyword vector to the taste
   vector, boosted by how many seeds surfaced it, penalized for over-represented genres.
5. Filter out anything already in any of the user's lists (incl. dismissed suggestions).
6. Cache results; refresh daily or on demand.

"For us" = combine both taste vectors (intersection-weighted) over the Together candidate pool.

This is deterministic, explainable ("because you liked X"), needs no ML infra, and runs fine
on-device for two people.

---

## 8. Privacy & security

- Vault data: owner's private CloudKit DB only; never in any CKShare; gated by
  LocalAuthentication; excluded from shared recommendations and from any export.
- TMDB API key: kept out of source control. Options: `.xcconfig` file gitignored, or
  Codemagic environment variable injected at build. (We'll wire the Codemagic env var.)
- No analytics/third-party SDKs phoning home in v1.
- Because it's CloudKit, the data lives in your and her iCloud accounts — not on any server
  we run.

---

## 9. Phased roadmap

**Phase 0 — Project setup** ✅ DONE
- XcodeGen project, bundle id, Codemagic pipeline (build + sign + TestFlight). Green build shipped.
- TMDB key wired via Codemagic env var.

**Phase 1 — MVP (single user, real value fast)** ✅ DONE (verified on device)
- Search (TMDB + AniList) → add → personal lists with states.
- Item detail with metadata + cover.
- Episode progress (season/episode numbers).
- Local-first via SwiftData.

**Phase 2 — Two users + Together**
- Partner pairing via CKShare.
- Together space + shared progress + Match view.
- Suggestion inbox.

**Phase 3 — Vault**
- Face ID–gated private collection, fully isolated.

**Phase 4 — Recommendations**
- Taste profiles + "For you" + "For us".

**Phase 5 — Polish**
- Widgets ("next up"), notifications (she suggested something), nicer art, settings.

---

## 10. Decisions (resolved)

1. **App name** — ✅ **BingeBuddy**.
2. **Target iOS** — ✅ both on latest iOS (you: iPhone 16 Pro Max). We target the latest
   stable iOS, so we can use the newest SwiftUI/SwiftData APIs freely.
3. **States** — ✅ include **Dropped** (states: Want / Watching / Finished / Dropped).
   ✅ **5-star** ratings.
4. **Vault fallback** — ✅ Face ID with **app passcode fallback**.
5. **Anime/series detail** — ✅ track **per-episode titles**, not just numbers.
6. **Core Data+CloudKit vs SwiftData** — leaning Core Data+CloudKit for shared-zone support;
   final call at Phase 2 (doesn't block MVP).

---

## 11. Codemagic notes
- `codemagic.yaml` with an iOS workflow: build, sign (App Store Connect API key), TestFlight.
- Inject `TMDB_API_KEY` as an encrypted env var; generate the `.xcconfig` at build time.
- Manual TestFlight distribution to just you + her (internal testers) — no App Store review
  needed for a two-person app.

---

## 12. Backlog / TODO (not yet scheduled into a phase)

★ = high impact / strong recommendation.

### Watching & tracking
- **Per-episode titles & checklist** — full episode list with titles you check off
  (TMDB `/tv/{id}/season/{n}`, AniList). Tracks numbers only today.
- ~~★ **Swipe "+1 episode"**~~ ✅ DONE — swipe a row in Library or the Together "Up next" list to
  bump the episode.
- **Auto-finish prompt** — when current episode hits the total, offer to mark it Finished.
- **Rewatch flag / count** — mark something as a rewatch instead of resetting progress.

### Discovery & info
- ★ **Where to watch** — show which streaming services a title is on (TMDB watch-providers
  endpoint). "It's on Hulu." Hugely practical.
- ★ **Browse / trending** — a discover row of trending & popular titles (TMDB trending) so
  Search isn't the only way in.
- **Runtime / time-to-finish** — estimate hours left in a series.

### Couple features
- ~~★ **Date-night picker**~~ ✅ DONE — shuffle button in Together picks a random title from your
  Matches + shared want/watching list.
- **Suggestion notes** — let the sender add a message when suggesting (field exists; no UI yet).
- **Reactions / mini-reviews** — a short note or emoji reaction per shared/partner title
  ("loved the finale").
- **Activity feed** — "Sarah finished Severance ★★★★★" so you each see what the other did.
- **Episode reminders** ✅ DONE (local notifications) — reminds you when a new episode airs for
  TV series you're Watching (TMDB next-episode air date; reschedules on app open). Anime (Jikan)
  next-air dates + partner-suggestion push still TODO (partner push needs the Push capability).

### Organization & insight
- **Custom tags / lists** — beyond the 4 states (e.g. "Cozy", "Spooky", "Rainy day").
- **Stats** — titles/hours watched this year, top genres, a fun year-in-review.

### Accounts & robustness
- **Sign in with Apple** — (deferred, not needed yet) upgrade from anonymous auth so data
  survives reinstalls and works across your own devices (iPhone + iPad).
- **iPad support** — currently iPhone-only; SwiftUI would mostly adapt for free.

### Polish
- **Home-screen widget** — "next up" / tonight's pick.
- **Pull-to-refresh, haptics, nicer empty states, loading skeletons.**
- **App icon redesign** — replace the placeholder gradient/play icon with real artwork.

### Housekeeping
- **Automate build numbers** — drive `CURRENT_PROJECT_VERSION` from Codemagic `$BUILD_NUMBER`
  instead of bumping `project.yml` by hand each upload.
