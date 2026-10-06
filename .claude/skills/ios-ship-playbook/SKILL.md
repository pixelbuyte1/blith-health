---
name: ios-ship-playbook
description: How Skintel and Blith actually get built, fixed, designed and shipped with this founder. Covers the working loop, design-first HTML mockups, the CI-only Swift workflow on Codemagic, every recurring fix and its root cause, App Review and signing fixes, the backend (API, AI model routing, Supabase), and the skills and tools that produced good results. Load it at the start of any Skintel or Blith session, before fixing a bug, before a design, and before touching CI or a release.
---

# iOS ship playbook (Skintel + Blith)

This is the record of what worked across many rounds of "fix this", "make a new design" and "release it".
Read it first. Trust the repos' `CLAUDE.md`, `HANDOFF.md` and `codemagic.yaml` over this file if they disagree.

## 1. The founder and how to work with them

- **No Mac.** Nothing is compiled locally. The only Swift compiler is Codemagic CI. Every guessed API costs a
  CI round-trip and the founder's build minutes.
- **The founder tests on a real iPhone (TestFlight).** They report bugs as screen recordings and screenshots,
  often several bugs in one message. Split the message into a numbered list and fix every item. Dropping one
  is the most common way to lose trust.
- **They want to see a design before it's coded.** "Show the design" / "show how it looks" means an HTML
  mockup (Artifact), never a CI build or simulator screenshot just to look.
- **Plain language, short replies.** Lead with the result. Give exact branch names, exact button paths
  ("Codemagic → app → Start new build → branch `X` → workflow `ios-release`"), and a short checklist of
  what's left. They often ask "which branch do I build?": answer with the literal name.
- **Never remove what you weren't asked to touch.** A rewrite once dropped paywall guard lines and broke
  free/Pro gating. Another time an unrelated refactor killed the Luna/Sol slide animation. Add, don't
  replace. Diff-check that existing guards, animations and gates survive.
- **Testing vs production.** When they say "testing", work on a separate branch (Blith: `blith-testing`).
  Push only explicit bug fixes to `main` through a PR. Ask nothing that a sensible default answers.
- **Releases are the founder's.** Agents run only `ios-ci`, once per push that needs it. Never start
  `ios-release`, `ios-setup` or `ios-release-check` unless the founder asks for it in that same session.
  Never submit to App Review or change App Store Connect state.
- **Usage is precious.** Don't use screenshots, extra agents or simulator runs unless they're needed. Batch
  fixes into one push, and stop PR polling when asked.

## 2. The loop that produced the best results

1. **Restate** the asks as a numbered list (bugs + design + questions), including the throwaway lines.
2. **Find the root cause** before editing: read the real code (`grep` declarations), and quote file:line in
   the commit body. Every good fix commit says "Cause: …" then "Fix: …".
3. **Design first** for anything visual: build an HTML mockup (Artifact, Design canvas type for multi-screen),
   get a reaction, then implement. Research first for a new direction (deep-research skill).
4. **Implement small**: one concern per commit, the existing tokens and components, no hex outside the theme
   file.
5. **Verify locally what you can**:
   - `swiftc -parse <file>` on every Swift file you touched;
   - `swift test` in the core package (`SkintelCore` / `BlithCore`), which runs on Linux;
   - `npm run build` plus `npx eslint` on touched files for the web/API.
6. **Push, open a PR, start one `ios-ci` via the Codemagic API**, and wait with a background poller (below).
7. **Inspect the CI screenshots** from the artifact zip. Crop the region in question and sample pixel values
   with PIL. Numbers (e.g. RGB `255,255,228` = clipped white) found the real cause twice when eyeballing didn't.
8. **Iterate once more if needed**, then report: what changed, what was verified (CI green, screenshot), and what's left.

## 3. Codemagic, the backend of shipping

- **API.** `curl https://api.codemagic.io/builds -H "x-auth-token: $CM_API_TOKEN"`.
  - Start a build: `POST /builds` with `{"appId", "workflowId":"ios-ci", "branch"}`.
  - Status: `GET /builds/<id>`; watch `build.status` and each `buildActions[]` status.
  - Artifacts: the `artefacts[].url` zip. Screenshots are under `build/screenshots/<device>-NN-name.png`.
  - The token lives only in the environment. Never echo it, commit it or write it to the repo.
- **Waiter**: a small script loops `GET /builds/<id>` every 25 s until the status is finished, failed, canceled
  or timeout. Then it prints each step's status and the `error:` lines of the failed step's log. Run it with
  `run_in_background` and the max timeout. The Codemagic queue can sit for hours, so don't burn turns polling.
- **App ids**:
  - Blith: `6abecf04b829335fcd57eabc`, for `pixelbuyte1/blith-health`. `6abb0f18…` is the old app from
    before the repo transfer.
  - Skintel: its own app, branch per the PR.
- **After a repo transfer**, webhooks stop starting PR builds, so start them through the API. The git remote
  still redirects (the "This repository moved" line is harmless). GitHub MCP calls still use the old owner
  name the session is scoped to.
- **Billing**: "BILLING_NOT_ENABLED" means the founder must enable billing. Mac mini minutes cost money.
  Xcode Cloud is the free alternative (25 h/month), but it needs Apple-side setup by the founder.
- **ios-ci triggers** (Blith): only `main` and PRs into `main` that change `ios/`, `scripts/` or
  `codemagic.yaml`. Markdown-only changes don't build.

### Signing / release fixes already made (don't redo, don't regress)

| Symptom | Cause | Fix |
|---|---|---|
| Release fails before any work (Skintel) | Workflow named integration `skintel_app_store_connect`, env group `ios_release`; real names are `codemagic1` and `skintel_ios_release` | Point the yaml at the names that exist |
| "attribute value already used" for the build number | Apple burns a failed build's number; ASC still reports the last processed one | Use the max of (ASC latest + 1, Codemagic build counter) |
| Sign-in broken on TestFlight only | Release copied `Config.example.xcconfig` with a truncated Supabase key | Generate xcconfig from env vars, escape `//`, and fail if the key isn't a 3-part JWT |
| `--certificate-key` rejected (Blith) | Key pasted on a phone: long dashes, lost BEGIN/END lines, non-breaking spaces | Rebuild a clean PEM in the script |
| Can't create a Distribution cert | Apple allows 3 per account | Reuse the saved cert (`ios_signing` identity), as Skintel does |
| "No matching profiles found for com.blith.health" | No App Store profile in the Codemagic account | Create the profile during the build with the ASC key (PR #22), plus a widget profile via `WIDGET_RID` |
| Widget extension unsigned | The extension needs its own profile | Fetch/create profiles for the app and `*.widgets` |

## 4. App Review / App Store Connect fixes catalogue

| Issue | Fix |
|---|---|
| ITMS-90713 icon | Top-level `CFBundleIconName: AppIcon` in project.yml and the committed Info.plist; 1024 icon full-bleed, sRGB, no alpha, no manual rounding |
| Error 90474 orientations | Truly iPhone-only: `TARGETED_DEVICE_FAMILY=1` on every target config (target settings override the project) |
| Error 90683 (Blith) | `requestAuthorization(toShare:read:)` needs both `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` |
| 2.3.8 placeholder icon | Render the real brand mark |
| 5.1.1(iv) camera pre-screen | No custom "allow camera" pre-prompt that steers the choice; a neutral explanation then the system prompt |
| 2.1 (Blith) | Accurate AI consent listing exactly what goes to OpenRouter; no feature promises not in the build (Huawei); review notes; a screen recording on a physical iPhone |
| Subscriptions | Product ids must match between `SubscriptionService.ProductID` and `api/_apple.ts`; the server verifies the JWS (`jwsRepresentation` is on `VerificationResult`, not `Transaction`); never grant Pro client-side |
| Trials | Apple offers free trial lengths (3 days, 1 week…) as an introductory offer on the subscription; the design follows whichever is configured |

## 5. Bug-fix catalogue (root causes worth remembering)

**SwiftUI / iOS 26**
- **Glass isn't a hit target.** On iOS 26 `.glassEffect` doesn't hit-test, so only the glyph or text inside a
  glass button was tappable. That covered the scanner close and torch, the "Type it" pills and the AM/PM
  toggle. Fix: `.contentShape(Circle())` / `.contentShape(RoundedRectangle(...))` on the label.
- **Tab bar press-and-slide.** One `DragGesture` across the glass capsules moves the selection pill on a
  spring. The screen switches live as you slide, with a haptic tick per tab. Use non-interactive glass and a
  zero-spacing `GlassEffectContainer` so the capsules don't stretch into the FAB. Keep visited tabs alive like
  `TabView`. Keep the scanner camera stopped until the slide settles, and keep a VoiceOver action.
- **Composer under the tab bar.** Reserved space was applied outside the `NavigationStack`, so the screen
  must reserve it itself. Hide the bar while the keyboard is up.
- **Animations dying after unrelated changes** (Luna/Sol pill): don't depend on a `withAnimation`
  transaction surviving an `@AppStorage` round-trip; animate on the value in the view itself.
- **Page drifting sideways while scrolling** (Blith Today/Body): there was no horizontal ScrollView; a
  slightly wide child let the page drift. Pin the content with `.containerRelativeFrame(.horizontal)` after
  the padding.
- **iOS 26 tab bar collapsing to a floating circle** is system behaviour (minimise on scroll), not a bug.

**State / data**
- **Pro members seeing paywalls**: gates read `isPro` before the subscriptions row loaded, or after a failed
  fetch. Gate on `loaded` first, and retry or open after load.
- **"Unexpected reply from the server"**: the API didn't select `user_id` but the iOS model required it, so
  decoding failed. Fix both sides (return the field, make the client tolerant). Day keys must use the
  device's time zone, not UTC.
- **Persisted stores**: a `try?` decoder drops the whole file on any decode error. New fields must be
  optional or defaulted. Grep every init, tests included.
- **Injectable clocks**: no `isDateInToday` or `Date()` inside a function that takes `now:`.
- **Name collisions**: the core `Product` shadows `StoreKit.Product`, so qualify StoreKit types.

**3D body (Blith, SceneKit)**, in the order the fixes were found:
1. Muscles poking through the translucent skin: inflate the shell along its normals. A uniform 1.6 cm made
   the face and hands puffy. Region offsets with 8-pass smoothing came next. Final: per-vertex offsets
   measured offline (`design/body3d/skin_offsets.py`, scipy cKDTree against the muscle mesh, 3 mm margin),
   shipped as `skin_offsets.bin` ("BLO1", u32 count, f32 per vertex), with region offsets as the fallback.
2. Head colour mismatch: the shell covers the head too, over an opaque head cap in the muscle tone set 5 mm
   inside.
3. Pale outline around the body: the translucent shell showed the background through the gap. Fix: an
   opaque backing (the skin's back faces, `cullMode = .front`, constant colour) behind everything.
4. Body washed out to cream, tendons white: `wantsHDR` turns on auto exposure, which brightens for the dark
   chamber. Use `wantsExposureAdaptation = false` and `exposureOffset = 0.2` on the muscle layer; the figure
   layer keeps auto. Pixel sampling proved it (R = 255 everywhere).
5. Selection: bloom on a highlight above the threshold gave jagged white patches and a red halo. Use a soft
   tint strongest at the edges, and lower bloom per layer.
6. Don't step shell opacity per region: per-element opacity follows triangle edges and shows as a jagged
   collar.

**AI / backend**
- Scans and Ask were expensive (Opus, 8K budgets). Route them through one helper:
  - Scans: Gemini Flash Lite, then a fast GPT model on OpenRouter, with Haiku as the fallback; trimmed
    output budgets.
  - Ask: branded model names (Skintel "Luna"/"Sol"), validated server-side so the app can't pick a raw
    provider model.
  - Old chat turns are trimmed.
- Run lookups in parallel (Open Beauty Facts + Open Food Facts).
- Blith's OpenRouter key is in the app bundle and can be extracted. It needs a server proxy before a public
  launch. Rotate keys the founder pasted into chat.

## 6. Design knowledge

**Process that worked.**
- Deep research first, then a multi-screen HTML canvas (Artifact "Design" type: `canvas.json` + one
  `.dc.html` per artboard).
- Tab bars link the artboards and each screen has a `theme` tweak. CSS tokens on `.bl` with a
  `[data-theme=light]` override. Compute chart paths in `renderVals()`.
- Then a token-by-token mapping into `Theme.swift`.
- Save the canvas source in the repo (`design/<name>/`) with a README of tokens.

**Skintel** (women 20–40; a warm brand):
- Colours: cream `F4EDE0`, clay `A35848`, ink `1A1814`; no yellow (caution is clay).
- Type: Instrument Serif / DM Sans / JetBrains Mono.
- Tokens live in `ios/Skintel/Skintel/DesignSystem/Tokens/`.
- Mascot: the terracotta drop, as a native SwiftUI package (`SkinstelMascot`), placed at real moments.
- Paywalls: full-screen hard walls ("Get Skintel+", never "buy"), with an animated demo of the locked feature.
- Free users get sample bottles on an empty shelf and one-time tips.

**Blith 2.0** (men 20–45, health data):
- Dark first with a real light mode.
- Colour only where it means something:
  - status, for readiness only: Primed teal `3FD0B0`, Steady amber `F2B53E`, Strained coral `F0545E`;
  - signals: load `4DA3F7`, sleep `8C9BF0`, vitals `7CCBE6`;
  - base `0C1014`; primary action sand `D9CDB8`.
- Status = word + glyph + number. Readiness is never a percentage.
- No gauges or rings: range bars (your usual as a band), band-and-line trends, bars from zero.
- Missing ≠ zero: hollow or dashed vs a stub.
- Condensed bold tabular numerals.
- Glass only on the tab bar and the Ask composer. Motion happens once; no glow or pulsing.
- Streaks read "5 of the last 7 nights".
- Ask answers in the order Today → Usual → Context → Suggestion, plus a "Based on" line.

**"Vibe coded" tells to avoid**: purple gradients, neon glow, identical cards, emoji, Inter/Roboto, dials
everywhere, red/green status alone, percent scores, invented data presented as real.

## 7. Skills and tools: when each paid off

| Need | Use |
|---|---|
| New visual direction | `anthropic-skills:deep-research` (coordinator + Sonnet researchers + report writer), then the Artifact Design canvas |
| Show a design | Artifact (quickstart → type), never a CI build |
| Audits | Repo skills `advisor`, `appstore-check`, `ios-audit`, `qa`, `design-review`, `security-review`, `ship-check` |
| Platform APIs | `all-ios-skills:*` / `apple-skills:*`: scenekit, swiftui-liquid-glass, storekit, widgetkit, healthkit, app-store-review |
| Parallel grunt work | Subagents on Sonnet (search, boilerplate, tests), only when the founder agrees to spend usage |
| PR follow-up | Subscribe to PR activity and one safety-net check-in; stop when asked |
| Pixel checks | Python PIL: crop, scale, sample RGB from CI screenshots |

## 8. Never

- Commit or print keys (OpenRouter, Codemagic token, Apple .p8, Supabase service role, Stripe).
- Push to `main`, force-push someone else's branch, or start release workflows uninvited.
- Put model identifiers in commits or PRs (beyond the required attribution trailer).
- Ship synthetic data as measured, medical claims, or missing data drawn as zero.
- Claim "it builds/works" before `ios-ci` is green on that commit.
