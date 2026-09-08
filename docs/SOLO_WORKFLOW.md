# Solo Workflow — Running the Help Line Alone

Built around **asynchronous intake and confirmed appointments**. No walk-in live
line or instant-answer promise. Review each request within two business days,
check `LEGAL_SCOPE.md`, and confirm the service, full price and exact deadline
or appointment before sending a payment link. Only accept work you can deliver
on time. See [SERVICE_DELIVERY.md](SERVICE_DELIVERY.md) for the menu and delivery
requirements.

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
5. **Put the toolkit on your phone:** open `…/operator.html` on your phone and
   use Share → Add to Home Screen. That gives you one-tap access to the reply
   templates (with copy buttons), the pre-send scope checklist, and emergency
   numbers wherever you are. Tell clients they can do the same with the main
   page to get the "app" without any App Store.
6. **Read `docs/LEGAL_SCOPE.md` fully once**, and skim it again monthly.

## Daily intake review (allow separate time for paid work)

1. **Open the inbox and scan for emergencies first.** Anything describing an
   emergency symptom gets Template 1 (emergency redirect) *immediately*, before
   you touch anything else.
2. **Triage the rest:**
   - Needs a vet → Template 2, label `Referred to Vet`.
   - Medication/dosing ask → Template 4 (always refuse the dose).
   - Eligible general care question → confirm the requested service and price,
     collect needed context, agree the deadline, and then send the payment link.
     After payment, personalize the educational answer using Template 3.
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

- **Honor the confirmed deadline.** Focused written answers are due within one
  business day after confirmation and payment; detailed guides within two.
  Business days are Monday–Friday, excluding U.S. federal holidays, Pacific Time.
- **Calls and live text are appointments only.** Reserve 20 minutes for a text
  session or 30 minutes for a phone session, plus time for the emailed recap.
  An added phone number is not permission to change the selected service.
- **It's okay to say "that's outside what I can help with."** Template 2 exists
  for exactly this.
- **Plan days off around existing commitments.** Do not accept payment for a
  deadline you cannot meet; offer another appointment or decline before payment.

## Growing later (not now)

When volume outgrows one person, the order of cheap wins is:

1. **FAQ section on the site** — add a card to `index.html` answering your top
   repeat questions (deflects email before it's sent).
2. **Auto-reply** on the inbox confirming receipt + repeating the emergency
   redirect info.
3. Only after those: a second volunteer, a proper form backend, etc.
