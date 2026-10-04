# Release & App Store checklist

Status: ✅ done in code · 🔧 needs an external step · ⚠️ known gap

| Area | Status | Notes |
|---|---|---|
| App icon 1024 (light + dark), no alpha | ✅ | `Assets.xcassets/AppIcon.appiconset`, sources in `design/` |
| Display name / bundle id | ✅ | Blith / `com.blith.health` (`ios/project.yml`) |
| iPhone only, portrait | ✅ | `TARGETED_DEVICE_FAMILY 1` |
| HealthKit entitlement | ✅ | `com.apple.developer.healthkit` (read-only; no clinical records) |
| HealthKit usage string | ✅ | `NSHealthShareUsageDescription` explains the purpose specifically |
| Permissions asked in context, minimum types | ✅ | Onboarding explains first; user picks categories; only used types requested |
| No dark patterns around HealthKit | ✅ | App never claims access was granted; "no data" states explain how to check access |
| App works without Health data | ✅ | Explicit, labelled sample-data mode (useful for App Review) |
| Health data not used for ads / not in iCloud | ✅ | Local only; no analytics SDKs |
| Third-party AI disclosure + consent (5.1.1, 5.1.2) | ✅ | Consent sheet before first AI request; off by default until chosen; revocable in Profile |
| Privacy manifest | ✅ | `PrivacyInfo.xcprivacy`: no tracking; health, fitness, user content (AI, unlinked); UserDefaults CA92.1 |
| Privacy policy URL | ✅/🔧 | `docs/PRIVACY.md` (linked in-app). Use the same URL in App Store Connect |
| Medical claims | ✅ | Pattern language only, causation caveats, "not a medical device" in Profile and sheets, urgent-symptom screen |
| Data deletion | ✅ | Profile › Delete all Blith data (no accounts exist) |
| Export compliance | ✅ | `ITSAppUsesNonExemptEncryption = NO` |
| Secrets not in repo | ✅ | OpenRouter key comes from gitignored `Secrets.xcconfig` or the Codemagic `blith_ai` group |
| Embedded API key | ⚠️ | The OpenRouter key ships inside the app binary. Before a wide release, move AI calls behind a small server proxy with per-install rate limits |
| App Store Connect app record | 🔧 | Create the app once in App Store Connect (My Apps › + › New App, bundle ID `com.blith.health`). Apple's API cannot create apps |
| App ID + HealthKit capability | ✅ | Registered by the `ios-setup` workflow (idempotent): `com.blith.health` with HealthKit |
| Codemagic signing | ✅ | `ios-release` uses `ios_signing`: the Apple Distribution certificate and its private key are saved in the Codemagic account's Code signing identities (same as Skintel), and Codemagic fetches or creates the App Store profile for `com.blith.health` through the App Store Connect integration `codemagic1`. No key in environment variables. |
| App Privacy answers | 🔧 | Health & Fitness + User Content: collected only when AI answers are on, not linked, not tracking, App Functionality |
| Screenshots | 🔧 | `ios-ci` produces simulator screenshots with sample data as a starting point |

## Shipping a TestFlight build

One-time:

1. In App Store Connect, create the app: My Apps › + › New App › iOS, name Blith, bundle ID `com.blith.health`, any SKU. This is the only step Apple doesn't allow through the API.
2. Codemagic workflow `ios-setup` (already run) registers the App ID with HealthKit. Re-run it any time; it changes nothing that already exists.

Every release:

3. Start the `ios-release` workflow in Codemagic on `main`. It:
   - sets the team ID from the App ID,
   - finds or creates the distribution certificate and App Store profile,
   - archives with the next build number from App Store Connect,
   - signs, builds `Blith.ipa`, and uploads it.

   The IPA is kept as a build artifact even if no app record exists; in that case the upload step is skipped and says why.
4. When Apple finishes processing (a few minutes), the build appears in TestFlight. Add yourself under Internal Testing. External testers need Beta App Review and the privacy policy URL below.

`ios-release-check` builds an unsigned Release archive for a device; use it to catch Release-only problems without touching Apple accounts.

Notes:

- Apple allows 3 Distribution certificates per account, so Blith shares the one Skintel uses. The Codemagic account that runs `ios-release` must have that certificate saved under Code signing identities.
- The OpenRouter key is embedded in TestFlight builds through the `blith_ai` group. Move AI calls behind a server proxy before a public release.
