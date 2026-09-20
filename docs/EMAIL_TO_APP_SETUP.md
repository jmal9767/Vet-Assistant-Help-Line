# Email-to-App Setup

Client emails only appear in the iOS app when they create `Question` records in CloudKit.

## Current fallback mode

`index.html` currently has:

```js
var WORKER_URL = "REPLACE_WITH_YOUR_WORKER_URL";
```

With that placeholder, the website opens the client's email app and sends a normal email to `HELPLINE_EMAIL`. Those messages go to your mailbox only. They do not appear in the private iOS app.

Use a public help-line email alias for `HELPLINE_EMAIL`, not your personal email. The alias can forward to your private inbox, but clients should only ever see the public address.

## Option 1: Website form directly to app

Deploy `relay/cloudkit-worker.js` and set:

```js
var WORKER_URL = "https://your-worker.your-subdomain.workers.dev";
```

Then website submissions create CloudKit `Question` records and appear in the iOS app.

## Option 2: Real inbound email to app

Use an inbound email provider, such as SendGrid Inbound Parse or another email routing service, and point it to:

```text
https://your-worker.your-subdomain.workers.dev/sendgrid/inbound?secret=YOUR_WEBHOOK_SECRET
```

Then emails sent to the configured help-line address can be converted into CloudKit `Question` records.

For anonymous replies, send responses from the same public help-line mailbox or a provider-managed alias. If you reply from a personal email account in Mail, the client will see that personal address.

## Required CloudKit fields

The CloudKit `Question` record type should include the fields used by the app and worker, including:

- `name`
- `email`
- `phone`
- `preferredReply`
- `requestedService`
- `petName`
- `species`
- `age`
- `category`
- `urgency`
- `question`
- `attachmentSummary`
- `sourceChannel`
- `conversationStatus`
- `paymentStatus`
- `paymentMethod`
- `paymentAmount`
- `paymentLink`
- `signedConsentName`
- `signedConsentAt`
- `status`
- `submittedAt`
