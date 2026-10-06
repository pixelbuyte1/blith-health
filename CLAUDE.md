# Blith — repo guide for AI agents

Blith is a native SwiftUI iPhone app that turns Apple Health history into daily scores measured against the
person's own usual range (Readiness, Sleep, Load), plus overnight readings, a 3D body map and an assistant.
Overview: `README.md`. Design language: `docs/DESIGN.md`. Architecture: `docs/ARCHITECTURE.md`.
Privacy promises: `docs/PRIVACY.md`. Releases: `docs/RELEASE.md`.

## The one rule that matters

**There is no Mac and no local Swift compiler.** The only build is Codemagic `ios-ci` (`codemagic.yaml`), roughly a
few minutes per run. Before using any project type, property, initializer label, enum case or route, grep its real
declaration and match it exactly. Never write project APIs from memory. Re-read your own diff as a compiler would
before pushing.

## Layout

| Path | What |
|---|---|
| `ios/Blith/` | SwiftUI app: `App/` (tabs, `AppRouter`), `DesignSystem/` (`Theme.swift` tokens, `Components.swift`, `Instruments.swift`), `Charts/`, `Features/<Area>/` |
| `ios/BlithCore/` | Swift package: models, sync, store, analytics, insights, assistant tools, tests, `BlithCLI` |
| `ios/project.yml` | XcodeGen spec. CI runs `xcodegen generate`, so new Swift files under `ios/Blith` are picked up; never hand-edit the `.xcodeproj` |
| `design/` | Icon, symbols, 3D body generator, screenshots (the PNGs predate the current palette) |

## Commands

```bash
cd ios/BlithCore && swift test                 # core tests (macOS, or Linux with a Swift toolchain)
swift run BlithCLI insights balanced            # assistant and insights against sample data
cd ios && xcodegen generate                     # only on a Mac
```

## Working rules

1. Branch from `main`, one concern per branch, open a PR; the founder reviews and merges. Never push to `main`.
2. Plan first in a few lines; keep diffs small; find the root cause before fixing a bug.
3. Verify: grep-check every API you touch, run BlithCore tests when you change core, then Codemagic `ios-ci`.
   Never say the app "builds" or "works" until `ios-ci` is green. Agents never start a release workflow.
4. Design: use `Palette`, `Typo`, `Space` and `Radius` tokens only; no hex literals outside `Theme.swift`
   (Body3D's imaging-chamber lighting is the known exception). Status is always colour + glyph + word.
   `Palette.note` (rust) means a reading outside the person's usual range, or their own notes, and nothing else.
   Mono labels never go below 11 pt. Readiness is a score out of 100, never a percentage.
5. Honesty: no medical claims or diagnosis words, no synthetic data presented as measured, missing data never
   drawn as zero. The AI consent copy must list exactly what is sent to OpenRouter.
6. Secrets: never commit keys. Known issue: the OpenRouter key is injected into Info.plist at build time and can be
   extracted from the app; it needs a server proxy.
7. Token economy: read only the lines you need, avoid screenshots and extra agents unless asked, and keep PR
   check-ins to one cheap status call every 6 hours.
8. Codemagic minutes are limited. Agents use only `ios-ci`, once per push that needs it, and only to verify code.
   Never start `ios-release-check`, `ios-setup` or `ios-release` (the founder starts releases and publishes to
   TestFlight). Never run CI just to get screenshots or a look at a design: show how a screen will look with a
   design mockup artifact (HTML) instead. Batch fixes into one push so a PR costs as few builds as possible.

## Builds and CI minutes

Codemagic build minutes are limited. Only two workflows are ever used:
- **`ios-ci`** (core tests, simulator build, screenshots, no signing). It runs only on pushes to `main` and on pull
  requests into `main` that change `ios/`, `scripts/` or `codemagic.yaml`; markdown-only changes don't build.
- **`ios-release`** (TestFlight). The founder starts it from `main`. Agents start it only when the founder asks for it in
  that same session, and never submit to App Review.
Never run the app on a phone or simulator yourself, and never start other workflows (`ios-release-check`, `ios-setup`)
to "try things". To show how a design will look, build a mockup page (artifact) instead of a build. Merge to `main`
first when a release is wanted: `ios-release` builds the branch you pick, and an unmerged branch is not released by default.
The Codemagic API token, like every key, is never written to a file or committed; use it only for what the founder
asked in that session (start `ios-ci` or `ios-release`), and the founder rotates it afterwards.

## Redesign 2 (in progress)

Palette moved to paper, ink and teal (PR #10). Next: Today rebuilt with one hero per situation (readiness with a
Watch, movement without), then four tabs (Today, Trends, Body, Ask). Mockups live in the "Blith Redesign 2" board.
