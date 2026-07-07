# BingeBuddy — Full Audit & Product Roadmap

*Audited 2026-07-06, build 35 (v0.12.3), commit `93be72f`. Every Swift file, the Firestore
rules, the Codemagic pipeline, and the project config were reviewed.*

---

## 1. Overall verdict

The app is in **good shape for what it is**: a clean, small (~3,500-line) codebase with
sensible layering (providers → `MetadataService` → stores → views), realtime two-person sync
that works, offline support for free via Firestore's local cache, and a vault whose privacy
model is genuinely sound (local-only SwiftData, PIN hashed in Keychain, biometrics that
deliberately don't fall back to the device passcode).

The metadata layer has been battle-hardened through real outages (AniList disabled, Jikan
504s) and now has a resilient multi-source design: TMDB for film/TV, Jikan for anime lookups,
Kitsu for anime charts (mapped back to MAL ids), AniList kept as a legacy resolver. That
redundancy is a real strength most hobby trackers don't have.

**But** there is one security hole that must be fixed before this data grows or the app ever
goes public, a handful of real bugs, one existential data-durability risk, and a set of
missing features that separate "works great for us" from "best tracker on the App Store."

---

## 2. Security findings

### 2.1 HIGH — Any signed-in user can enumerate (and join) every household

`firestore.rules` says:

```
match /households/{householdId} {
  allow read: if request.auth != null;
  ...
  allow update: if request.auth != null
                && (request.auth.uid in resource.data.memberUids
                    || request.auth.uid in request.resource.data.memberUids);
}
```

In Firestore rules, `read` covers both `get` **and `list`**. Anonymous sign-in is open to
anyone (and the Firebase API key ships inside the IPA, as it must). So anyone can:

1. Sign in anonymously (no barrier),
2. **List the entire `households` collection** — every household id (= join code), name, and
   member names,
3. Use the update rule's join clause to **add themselves to any household**, which then grants
   full member access to that household's library, suggestions, and prefs via the
   subcollection rule.

Today the blast radius is two users on internal TestFlight, so this is a *moderate* live risk
— but it's a one-line-of-intent fix and a genuine privacy incident if the app ever goes
public. **Fix (Phase A):**

```
// get by exact code is fine (join-by-code needs it):
allow get: if request.auth != null;
// list only returns households you belong to:
allow list: if request.auth != null
            && request.auth.uid in resource.data.memberUids;
// join: only append yourself, cap at 2 members, touch nothing else:
allow update: if request.auth != null && (
  // existing member editing
  request.auth.uid in resource.data.memberUids
  // OR a join that only adds self to a 1-member household
  || (
    !(request.auth.uid in resource.data.memberUids)
    && request.resource.data.memberUids.hasAll(resource.data.memberUids)
    && request.resource.data.memberUids.size() == resource.data.memberUids.size() + 1
    && request.resource.data.memberUids.size() <= 2
    && request.auth.uid in request.resource.data.memberUids
  )
);
```

This preserves the exact join-by-code flow the app uses (`getDocument` + `updateData`) while
killing enumeration and stranger-joins-a-full-household. The app's own membership query
(`whereField("memberUids", arrayContains: uid)`) still passes the new `list` rule.

### 2.2 LOW — TMDB read token is baked into the binary

The Codemagic "Inject secrets" step writes the token into `Secrets.swift`, so it's extractable
from the IPA. For a free-tier read-only token on a personal app this is a widely-accepted
risk (most shipped apps do exactly this). If the app goes public and the token gets abused,
the options are a tiny proxy (Cloud Function / Worker) or rotating the key. Documented, not
urgent.

### 2.3 OK — Vault threat model

Vault items never leave the device (local SwiftData store, never Firestore). PIN is
SHA-256-with-salt in the Keychain (`ThisDeviceOnly`). Face ID path disables the device-passcode
fallback on purpose. Two acceptable notes: iOS full-disk encryption is the at-rest protection
(fine); and anyone who can *unlock the phone itself* still can't open the vault without the
separate PIN/FaceID — which was the design goal.

---

## 3. Bugs found (ordered by user impact)

1. **Vault likely re-locks while you're using it.** `VaultContainerView.onDisappear { vault.lock() }`
   also fires when you *push* a vault item's detail screen (NavigationStack calls the parent's
   `onDisappear` on push). Result: open vault → tap an item → go back → you're at the lock
   gate again. Fix: lock on `scenePhase != .active` (app backgrounded) instead of
   `onDisappear`. *(Verify on device; if it hasn't been noticed it's because the Face ID
   re-prompt is fast.)*

2. **Metadata never refreshes once set.** `LibraryStore.backfill` only fills fields that are
   `0`/empty. So: an airing anime that finishes keeps `totalEpisodes = 0` forever unless
   reopened before…, a TV show that gets a new season keeps the old `totalSeasons`, a poster
   change never propagates. Fix: on detail open, *diff* fetched details against stored fields
   and update when they differ (not only when empty).

3. **Catch-Up misses currently-airing shows.** It filters `totalEpisodes > 0`, which excludes
   airing anime (unknown totals) — the shows you're most likely to be behind on. Fix: include
   `watching` items with unknown totals using a "last aired episode" signal (TMDB
   `last_episode_to_air`; Jikan aired-episode counts where available).

4. **Episode reminders re-fetch everything on every app open.** The `.task(id: watchingKey)`
   in `RootView` re-runs `scheduleEpisodeReminders`, which fetches details for *every* watching
   TV/anime title (each Jikan call throttled at 0.55 s). With a big watching list that's slow,
   battery-hungry, and competes for Jikan rate limit with Browse. Fix: persist a
   `lastScheduledAt` + the watching-set hash; re-schedule at most once/day unless the set
   actually changed.

5. **Silent write failures.** Nearly all Firestore mutations are fire-and-forget (`try?` /
   no completion). If a write is rejected (rules change, quota, edge cases), the UI shows
   success and the change quietly vanishes on next sync. Fix: a small `writeError` publisher
   on the stores + a toast; not per-call ceremony, just one shared surface.

6. **Dismissed suggestions can come back as recommendations.** Dismiss deletes the doc, and
   nothing records the taste signal. SPEC §7 explicitly wanted dismissed suggestions excluded.
   Fix: on dismiss, also add the mediaKey to `hiddenRecs`.

7. **Duplicate suggestions.** Sending the same title twice creates two inbox cards
   (`addDocument` auto-id). Fix: deterministic doc id `sug_{toUid}_{mediaKey}` + merge.

8. **Minor:** Search fires only on keyboard submit (no as-you-type debounce); "Popular movies"
   row has no TV equivalent; suggestion `message` field exists but has no compose UI; star
   rating has small tap targets and no accessibility labels; `EpisodeSchedule`'s weekly anime
   reminder uses the JST broadcast weekday as a *local* weekday (can be off by a day for US
   time zones — worth a note in the reminder copy or a −1 day heuristic).

---

## 4. The existential risk: anonymous auth

Everything both of you have entered is keyed to two **anonymous** Firebase uids. Anonymous
credentials do not survive app deletion, and Apple can purge them on devices that haven't run
the app for a long time. If either phone loses its credential, that person's identity — and
with it write-access mapping, "mine vs hers," suggestions routing — is **unrecoverable**; the
data would sit orphaned in Firestore under a uid nobody can sign into again.

You deferred Sign in with Apple, which was reasonable to get moving. But for a "best product"
this is priority #1 infrastructure, and the right way is **account linking** (link the Apple
credential to the *existing* anonymous uid via `currentUser.link(with:)`) so all current data
stays attached. Doing it later — after years of watch history — is the same work with higher
stakes. It's also a prerequisite for App Store release (Apple requires account deletion for
apps with accounts, which implies real accounts).

---

## 5. What's already good (keep it this way)

- **Architecture:** small files, one responsibility each; providers behind a router; stores
  as the only Firestore touchpoints; views dumb. Easy to extend, easy to audit (this took an
  afternoon, not a week).
- **Two-person sync design:** one `items` collection with `ownerUid` + `scope` is the right
  shape for a couple; derived slices (`myPersonal`/`partnerPersonal`/`together`/`matches`)
  keep the views trivial. Firestore offline persistence means the app already works on a plane.
- **Metadata resilience:** three anime sources with graceful degradation, a real throttle
  (reserve-before-sleep), retries with backoff, and poster caching. This survived two actual
  upstream outages during development.
- **Vault privacy model** (see §2.3).
- **Recommendations:** explainable ("Because you liked X"), cheap, scope-aware, with synced
  per-user "not interested." The seed-weighting (finished > watching > want, rating-boosted,
  dropped excluded) is simple and sane.

---

## 6. Roadmap to "best show/movie/anime tracker on the App Store"

Phases are ordered so each ships something usable; A and B are corrective, C is the product
leap, D is the public-release gate, E is fit-and-finish. Effort is in build-cycles (≈ one
push + TestFlight install).

### Phase A — Hardening (1–2 builds + a console paste) ← do first
| # | Item | Notes |
|---|------|-------|
| A1 | **Fix Firestore rules** (§2.1) | Console paste; no app build needed |
| A2 | Vault re-lock fix (scenePhase) | + verify on device |
| A3 | Metadata refresh-on-open (diff, not fill-if-zero) | fixes stale episode counts |
| A4 | Catch-Up includes airing shows | last-aired-episode signal |
| A5 | Reminder scheduling budget (≤1×/day unless list changed) | perf + rate limit |
| A6 | Dismiss → hiddenRecs; dedupe suggestion docs | spec conformance |
| A7 | Shared write-error toast | kills silent failures |
| A8 | Firebase Crashlytics | you can't fix crashes you can't see |

### Phase B — Durability (2–3 builds) ← before trusting it with years of data
| # | Item | Notes |
|---|------|-------|
| B1 | **Sign in with Apple via anonymous-account linking** | keeps all existing data |
| B2 | Account deletion + JSON export | Apple requirement; also peace of mind |
| B3 | Automate `CURRENT_PROJECT_VERSION` from Codemagic build number | ends manual bumps |
| B4 | Unit tests for RecommendationEngine + provider decoding (fixture JSON) | pure logic, cheap, catches regressions the blind-build workflow can't |

### Phase C — The features that make it *the best* (each 1–3 builds)
Ranked by differentiation-per-effort:

1. **Episode-level checklist** — per-episode titles, air dates, check-off, "next unwatched"
   (TMDB `/tv/{id}/season/{n}`, Jikan episodes). Spec'd on day one, never built; this is the
   single biggest gap vs. TV Time / Sequel / MAL. Progress becomes "which episodes," not a
   counter, and Catch-Up gets exact.
2. **Where to watch** — TMDB watch-providers per title (+ region), with app deep-links.
   Answers the nightly "okay but where is it streaming" question.
3. **Import from MAL / AniList / Trakt / TV Time (CSV/XML)** — *the* adoption feature. Nobody
   switches trackers without their history; almost no small tracker does import well.
4. **Upcoming calendar** — a week/month grid of your shows' air dates (data already fetched
   for reminders). Pairs with a "tonight" section.
5. **Partner push notifications** — real pushes for "she suggested X" / "he finished Y."
   Needs FCM + a Cloud Function trigger (Blaze plan: ~$0/mo at your volume, but requires a
   card) — or keep local-only and skip. Decide when you get here.
6. **Widgets** — small: next-up episode; medium: tonight's date-night pick. High delight,
   moderate effort (needs an App Group to share data with the extension).
7. **Stats / Year-in-review** — episodes watched, hours, top genres, streaks; a shareable
   card. Fun, viral-ish, all data is local already.
8. **Notes, tags & rewatch** — `note` field exists with no UI; add custom tags ("Cozy,"
   "Spooky") and a rewatch counter.

### Phase D — App Store release gate (when/if you want it public)
- Real app icon + a branding pass (current icon is the Phase-0 placeholder).
- Onboarding for people *without* a partner (solo mode must feel first-class; pairing optional).
- **TMDB attribution** (required by their terms), plus Jikan/Kitsu credits screen.
- Privacy policy URL + App Privacy labels (data types: watch history tied to account).
- Account deletion (B2) — hard requirement.
- Rules hardening (A1) — mandatory before strangers can create accounts.
- App Review dry-run: the vault is a generic "private locked list" feature — fine as-is.

### Phase E — Fit & finish (ongoing)
- Search-as-you-type with debounce + cancellation.
- Loading skeletons instead of spinners; haptics on state changes/check-offs.
- Poster disk cache (URLCache tuning or file cache) for instant cold launches.
- "Popular TV" row alongside popular movies.
- Accessibility: Dynamic Type audit, VoiceOver labels on stars/steppers/swipes.
- iPad layout (one flag + a grid pass), then maybe Mac Catalyst.

---

## 7. Suggested sequence

1. **A1 today** (console paste, no build), then A2–A8 as one or two builds.
2. **B1–B2** next — durability before more feature weight.
3. Then C in the order above, shipping one feature per build cycle, testing as you go.
4. D only when you two decide you want it public; E threads through everything.

The honest summary: the foundation is better than most side projects — the gap between this
and "best tracker on the App Store" is (a) one security fix, (b) real accounts, (c) episode-
level tracking + import + where-to-watch, and (d) a coat of polish. All of it is reachable
with the workflow we already have.
