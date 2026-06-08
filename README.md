# BingeBuddy

A private watch-tracker for two people. iOS, built on Windows, shipped via Codemagic →
TestFlight. See [SPEC.md](SPEC.md) for the full design.

---

## How development works (Windows-only setup)

You don't have a Mac, and that's fine. Here's the loop:

```
edit code on Windows  →  git push to GitHub  →  Codemagic builds on a cloud Mac
        →  build appears in TestFlight  →  install on your iPhone & test
```

There's no local simulator or Xcode. Codemagic is the Mac. TestFlight is how you run it.

---

## Phase 0 — one-time setup checklist

Do these once. They're the boring-but-unavoidable account steps. Take your time; ask me
if any screen looks different than described.

### 1. Apple — register the app
You're already in the Apple Developer Program. 
1. Go to **appstoreconnect.apple.com** → **My Apps** → **＋** → **New App**.
2. Platform: **iOS**. Name: **BingeBuddy** (must be unique on the App Store — if taken, try
   "BingeBuddy Tracker" and tell me so I update the bundle id).
3. Bundle ID: choose **com.jessesmith.bingebuddy** if available. If you have to pick a different
   one, **tell me the exact string** so I match it in `project.yml` and `codemagic.yaml`.
4. SKU: anything, e.g. `bingebuddy01`. Save.
5. Note the app's **Apple ID** (a long number shown on the app's page) — you'll need it
   later as `APP_STORE_APP_ID`.

### 2. Apple — make an App Store Connect API key (lets Codemagic sign & upload)
1. App Store Connect → **Users and Access** → **Integrations** tab → **App Store Connect API**.
2. Click **＋**, name it `codemagic`, access **App Manager**. Generate.
3. Download the **`.p8` key file** (you can only download it once — keep it safe).
4. Note the **Key ID** and the **Issuer ID** shown on that page.

### 3. GitHub — create the repo
1. Make a free account at **github.com** if you don't have one.
2. Create a **new, empty private repo** named `bingebuddy` (no README, no .gitignore —
   leave it empty; we already have those locally).
3. Copy the repo URL (looks like `https://github.com/<you>/bingebuddy.git`).
4. Tell me the URL and I'll connect this local project to it and push.

### 4. Codemagic — connect & configure
1. Sign in at **codemagic.io** with your GitHub account; authorize it to see the repo.
2. Add the `bingebuddy` repo as an application.
3. **Integrations → App Store Connect:** the connected integration is named **`Codemagic02`**
   (reused from another project — one App Store Connect key works for all your apps).
4. **Environment variables:** create a group named **`bingebuddy`** and add:
   - `TMDB_READ_TOKEN` = your TMDB v4 token — check **Secure**.
   - `APP_STORE_APP_ID` = the app's Apple ID number from step 1.
5. Codemagic will auto-detect our `codemagic.yaml`. Start a build.

### 5. TestFlight — let yourselves in
1. After the first successful build, the app appears in **App Store Connect → TestFlight**.
2. Create an **Internal Testing** group named **Internal**; add your and your wife's Apple
   IDs as testers.
3. Install the **TestFlight** app from the App Store on both iPhones; accept the invite.

That's the whole pipeline. Once a build reaches your phone, Phase 0 is done and every
feature after is just code I write + a push.

---

## Project layout

```
project.yml        XcodeGen spec — defines the Xcode project (we edit this, not .xcodeproj)
codemagic.yaml     CI/CD pipeline (build + sign + TestFlight)
Sources/           SwiftUI source code
SPEC.md            full design & roadmap
```

## Secrets — never commit
TMDB token, `.p8` keys, and signing files stay in Codemagic / your machine, never in git.
`.gitignore` already blocks the common ones.
