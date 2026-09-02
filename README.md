# Vet Assistant Help Line

A free, one-person pet-care help line run by a veterinary assistant. Pet owners
submit general care questions through a simple web page; emergencies are
redirected to emergency veterinary services *before* they ever reach the queue;
everything else arrives by email as a structured request answered within
24–48 hours using pre-vetted templates.

**Designed for a solo operator:** no backend, no server costs, no live phone
line, and legal scope-of-practice guardrails built into every step.

## How it works

```
Pet owner visits the page
        │
        ├─ Emergency symptoms? ──► Redirected to ER vet / poison control (never queued)
        │
        └─ General question ────► Structured email lands in your help-line inbox
                                          │
                                  You reply within 24–48h
                                  using response templates
                                  (educational info only,
                                   refer-to-vet by default)
```

## What's in this repo

| File | Purpose |
|---|---|
| `index.html` | The public website: emergency triage, scope explanation, cost transparency ("What does it cost?"), and a detailed intake form with per-category guidance. No dependencies, hostable free on GitHub Pages. Installable to a phone's home screen as an app (PWA) — no App Store needed. |
| `operator.html` | **Your** page: tap-to-copy reply templates, pre-send scope checklist, one-tap emergency numbers. Add it to your own phone's home screen. |
| `manifest.webmanifest`, `sw.js`, `icons/` | PWA plumbing: app name/icon for "Add to Home Screen" and offline caching. |
| `VetAssistantHelpLine.xcodeproj` | Xcode project for the native iOS app (requires Xcode 16+). |
| `VetAssistantHelpLine/` | SwiftUI source for the iOS app — same three pieces as the site: Emergency, Ask, About tabs. |
| `docs/LEGAL_SCOPE.md` | What a veterinary assistant can and can't say — the guardrails for every reply. |
| `docs/RESPONSE_TEMPLATES.md` | Copy-paste replies for the six situations that cover nearly every question. |
| `docs/SOLO_WORKFLOW.md` | Setup steps and the 15–30 min/day routine for running this alone. |

## Launch checklist — getting the app into customers' hands

There is no separate customer download: **the website is the customer's app.**
Publishing it once puts it on every customer's phone who opens your link.

1. **Merge the pull request** into `main`.
2. **Set your help-line email:** edit the `HELPLINE_EMAIL` line near the bottom
   of `index.html` (questions are sent to this address).
3. **Turn on GitHub Pages:** repo **Settings → Pages → Deploy from a branch →
   `main`, `/ (root)` → Save**. A couple of minutes later your app is live at:

   **https://jmal9767.github.io/Vet-Assistant-Help-Line/**

4. **Share that link** — text it, put it on a business card, post it. Anyone who
   opens it is using the customer side of the app, and the page itself shows
   them how to add it to their home screen so it behaves like an installed app.
   `docs/share-qr.png` is a ready-made QR code pointing at the URL — print it
   or show it on your phone and customers scan straight into the app.
5. **Your side:** open `https://jmal9767.github.io/Vet-Assistant-Help-Line/operator.html`
   on your phone and add it to your home screen. Customer questions arrive in
   your help-line email inbox; you answer them from there using the toolkit's
   tap-to-copy templates.

## Using it as an app — without the App Store

Once GitHub Pages is enabled, both pages work as installable web apps:

- **Clients:** they open the site in Safari (iPhone) or Chrome (Android) and tap
  **Share → Add to Home Screen**. They get a real app icon that opens
  full-screen — no App Store, no download, always the latest version.
- **You:** open `…/operator.html` on your phone and add *that* to your home
  screen. It's your pocket toolkit: reply templates you can copy with one tap,
  the pre-send scope checklist, tap-to-call poison control, and the red-flag
  list for triage.

The `operator.html` page isn't linked from the public site, but it is publicly
reachable if someone knows the URL — it contains nothing sensitive (the same
templates are in this public repo).

## iOS app

Open `VetAssistantHelpLine.xcodeproj` in Xcode 16 or later and run. Before
shipping:

1. Set your help-line address in `VetAssistantHelpLine/HelplineConfig.swift`
   (`HelplineConfig.email`).
2. Set your own bundle identifier and signing team in the target's
   Signing & Capabilities settings (it ships with a `com.example` placeholder).
3. Add a 1024×1024 app icon to `Assets.xcassets/AppIcon`.

The app mirrors the website: an **Emergency** tab (red-flag signs, ER vet
locator, tap-to-call poison control), an **Ask** tab (structured form that opens
a pre-filled email — no backend), and an **About** tab (scope + disclaimer).

> **Practical note for a solo operator:** the website is live the moment you
> enable GitHub Pages and costs nothing, and clients can install it to their
> home screens with no App Store involved (see above). Distributing this native
> app to *clients* requires an Apple Developer membership ($99/yr) and App Store
> review — but you can run it on **your own iPhone for free**: open the project
> in Xcode, sign in with your Apple ID (Signing & Capabilities → your personal
> team), plug in your phone, and press Run. Free personal signing expires after
> 7 days, after which you just press Run again — fine for personal use, not for
> handing to clients. A reasonable path: launch with the website/PWA now, ship
> the App Store app only if you later want the storefront presence.

## Getting started

1. Create a dedicated email address for the help line.
2. Open `index.html` and set `HELPLINE_EMAIL` (near the bottom of the file) to
   that address.
3. Enable GitHub Pages: repo **Settings → Pages → Deploy from branch → main,
   / (root)**. Your site goes live at
   `https://<username>.github.io/Vet-Assistant-Help-Line/`.
4. Read `docs/LEGAL_SCOPE.md` before answering your first question.

Full details in [`docs/SOLO_WORKFLOW.md`](docs/SOLO_WORKFLOW.md).

## Important disclaimer

This service provides **general educational information only**. It is not
veterinary medical advice, diagnosis, or treatment, and does not create a
veterinarian–client–patient relationship. Scope-of-practice rules vary by
state — see `docs/LEGAL_SCOPE.md` and verify against your state's veterinary
practice act.
