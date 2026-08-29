# Solo Workflow — Running the Help Line Alone

Built around one principle: **asynchronous by default.** No live phone line, no
chat widget, no promise of instant answers. A solo live line means missed calls,
pressure to answer fast (where scope mistakes happen), and burnout. Email intake
with a 24–48 hour promise means you answer on your schedule, with time to check
`LEGAL_SCOPE.md` before every send.

## One-time setup (about an hour)

1. **Create a dedicated email address** for the help line (don't use your
   personal inbox). A free Gmail account is fine.
2. **Put that address in `index.html`** — edit the `HELPLINE_EMAIL` line near the
   bottom of the file.
3. **Publish the page free on GitHub Pages:** repo → Settings → Pages → deploy
   from the `main` branch, root folder. Your site will be live at
   `https://<username>.github.io/Vet-Assistant-Help-Line/`.
4. **In the help-line inbox, create three labels/folders:** `To Answer`,
   `Answered`, `Referred to Vet`.
5. **Read `docs/LEGAL_SCOPE.md` fully once**, and skim it again monthly.

## Daily routine (15–30 minutes, once or twice a day)

1. **Open the inbox and scan for emergencies first.** Anything describing an
   emergency symptom gets Template 1 (emergency redirect) *immediately*, before
   you touch anything else.
2. **Triage the rest:**
   - Needs a vet → Template 2, label `Referred to Vet`.
   - Medication/dosing ask → Template 4 (always refuse the dose).
   - General care question → Template 3, write the educational answer.
   - Money worries → Template 5.
3. **Before hitting send on every reply, run the 3-question check:**
   - Did I diagnose, dose, treat, or predict an outcome? → rewrite or refer out.
   - Did I discourage a vet visit in any way? → rewrite.
   - Is the disclaimer at the bottom? → add it.
4. **Label and archive.** Your `Answered` folder is your record book — never
   delete it.

## Weekly (10 minutes)

- Skim the week's questions. If the same question came up 3+ times, that's your
  cue for the FAQ (below) — answering it once on the site beats answering it
  weekly by email.
- Notice any reply where you felt unsure about scope? Re-read that section of
  `LEGAL_SCOPE.md` and tighten the matching template.

## Boundaries that keep this sustainable

- **Response window is 24–48 hours.** It's printed on the site; don't privately
  hold yourself to faster.
- **No live calls, no texting, no DMs.** If people find your number, reply once:
  "I handle all questions through the form at [site link] so I can give each one
  proper attention."
- **It's okay to say "that's outside what I can help with."** Template 2 exists
  for exactly this.
- **Take days off.** An async queue waits; that's the point.

## Growing later (not now)

When volume outgrows one person, the order of cheap wins is:

1. **FAQ section on the site** — add a card to `index.html` answering your top
   repeat questions (deflects email before it's sent).
2. **Auto-reply** on the inbox confirming receipt + repeating the emergency
   redirect info.
3. Only after those: a second volunteer, a proper form backend, etc.
