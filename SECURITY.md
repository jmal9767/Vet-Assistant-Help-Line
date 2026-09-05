# Security Policy

## Supported versions

Before the first App Store release, security fixes are applied to the latest code
on `main`. After release, fixes will also be applied to the current App Store
version; older builds will not be supported after an update is available.

## Report a vulnerability privately

Email [info@bayareaapps.com](mailto:info@bayareaapps.com?subject=Security%20Report)
with the subject `Security Report`. If GitHub private vulnerability reporting is
enabled and available to you, the repository's **Security → Report a
vulnerability** option is also acceptable. Do not open a public issue for a
suspected vulnerability.

Include the affected version, device and operating-system version, steps to
reproduce, the security impact, and any safe proof of concept. Do not include
real client questions, personal information, pet medical records, credentials,
or payment data. Use clearly fictional test data.

The maintainer will acknowledge a complete report within five business days,
investigate it, and coordinate a fix and disclosure when appropriate.

## Credentials and sensitive data

- Never commit API keys, App Store Connect private keys, signing certificates,
  provisioning profiles, environment files, or secret build configuration.
- Keep service credentials in the relevant provider's or deployment platform's
  protected secret store. They must not be embedded in the iOS app, website,
  test fixtures, logs, screenshots, or crash reports.
- Treat client contact details and submitted question text as private.
  Redact them before sharing diagnostics or reproduction steps.
- Revoke and rotate an exposed provider, signing, or API credential immediately,
  then review history and logs for unauthorized use. Do not overwrite the
  replay-ledger HMAC key: replacement alone would make prior redemption hashes
  uncheckable. For HMAC loss or exposure, pause paid acceptance and new sales,
  preserve the ledger and evidence, and execute a reviewed versioned-key/epoch
  recovery and purchase-reconciliation plan.

## Scope

Reports may cover the iOS app, public website, StoreKit purchase handling, and
the email-based question-submission workflow. Problems in third-party services
should also be reported to the affected provider.
