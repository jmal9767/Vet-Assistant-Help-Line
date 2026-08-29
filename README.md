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
| `index.html` | The public website: emergency triage, scope explanation, intake form. No dependencies, hostable free on GitHub Pages. |
| `VetAssistantHelpLine.xcodeproj` | Xcode project for the iOS app (requires Xcode 16+). |
| `VetAssistantHelpLine/` | SwiftUI source for the iOS app — same three pieces as the site: Emergency, Ask, About tabs. |
| `docs/LEGAL_SCOPE.md` | What a veterinary assistant can and can't say — the guardrails for every reply. |
| `docs/RESPONSE_TEMPLATES.md` | Copy-paste replies for the six situations that cover nearly every question. |
| `docs/SOLO_WORKFLOW.md` | Setup steps and the 15–30 min/day routine for running this alone. |

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
> enable GitHub Pages and costs nothing. The iOS app additionally requires an
> Apple Developer membership ($99/yr) and App Store review to distribute. A
> reasonable path is to launch with the website first and ship the app when
> you're ready.

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
