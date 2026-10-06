# Startup adjustments — October 5, 2026

The reported device failure has no crash log yet; these changes address startup fragility and verify launch independently of compilation.

- QuestionStore now initializes the explicitly entitled CloudKit container lazily instead of opening the default container during App initialization.
- Inbox refresh checks iCloud account availability and shows actionable connection errors inline, keeping tabs usable without repeated modal alerts.
- ContentView owns the initial refresh and foreground polling; InboxView no longer races it with an extra initial refresh.
- CI builds the iPhone app, runs model checks, then cold launches and relaunches it on a disposable simulator. Both launches must stay alive for ten seconds. A screenshot is saved with the run.

Simulator launch does not validate the physical iPhone provisioning profile, CloudKit account, push delivery, or approved owner device key. If a device failure remains, inspect the Xcode device console and signing entitlements rather than deleting client records or resetting the owner key.
