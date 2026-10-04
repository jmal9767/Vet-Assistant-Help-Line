# Deploy the care line

The public intake and backend must use the same service menu: Quick Question $5, Detailed Guidance $10, Phone Support $20, Community Access $0. Existing pending $30/$35 payment links remain valid for historical requests; new intake does not offer those services.

## Validate

```sh
cd relay
npm test
npm run check
npx wrangler deploy --dry-run
cd ..
node scripts/build-site.mjs
npx wrangler deploy --dry-run --config website.wrangler.jsonc
xcodebuild -project VetAssistantHelpLine.xcodeproj -scheme VetAssistantHelpLine -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

## Publish

Use the existing Cloudflare account and secrets. Deploy the backend and matching intake consecutively:

```sh
cd relay
npx wrangler deploy
cd ..
node scripts/build-site.mjs
npx wrangler deploy --config website.wrangler.jsonc
```

After publication, verify both service menus, consent fields, Community Access without checkout, and a paid request's checkout page. Test with clearly labeled fictional records; never use real client data for release tests. Check private-file access and expiry, PayPal capture retry and completion/refund reconciliation, and app inbox/notification/answer/archive behavior. Confirm the original merchant and all webhook subscriptions in PayPal.

Four files of 10 MB each are supported, with a 40 MB combined limit. Private URLs expire after 30 days; URL expiry does not delete stored objects. Verify retention and deletion procedures separately.

The backend supports an older Question schema: when CloudKit rejects a missing field, the backend preserves that value in a versioned JSON envelope within the existing `question` field. The app decodes that envelope for normal display and updates, and checkout reads payment fields from it. Client information is retained even before newer schema fields are added. Production roles, record types, and query indexes still need verification.

## CloudKit and iPhone distribution

The current Worker uses CloudKit Development. A development-signed operator app uses that environment. TestFlight/App Store builds use Production: export and verify the full Production schema, operator/relay roles, and indexes before switching the Worker. Do not import the partial `cloudkit/Question.ckdb` reference as a full container schema, grant broad client-record access, or change the production environment blindly.

For a private operator installation, use Xcode with the Bay Area Apps LLC team and the intended paired iPhone. A successful signed build does not prove device installation or CloudKit account access. TestFlight requires a distribution archive and App Store Connect processing.

## Rollback

Record each deployed version ID. `wrangler rollback <version-id>` restores a previous Worker version. Roll back the backend and intake as a matching pair if release validation fails. Keep backups and credential-bearing configuration outside the public repository.
