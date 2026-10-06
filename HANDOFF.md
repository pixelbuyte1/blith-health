# Blith — handoff for the coding agent

Read this first, then `CLAUDE.md`, `docs/DESIGN.md` and `docs/ARCHITECTURE.md`. Written 1 Oct 2026. It records what
happened, what is decided, what is built, and exactly what is left, in build order. When this file and a mockup
disagree, the code and `docs/DESIGN.md` win; tell the founder about the gap.

---

## 1. Rules that matter most

1. **No Mac, no Swift compiler here.** The only build is Codemagic `ios-ci` (`codemagic.yaml`). Before you use any
   project type, member, initializer label, enum case, route or token, **grep its real declaration**. Never write APIs
   from memory. Re-read your diff as a compiler would. Never say it "builds" until `ios-ci` is green.
2. Branch from `main`, one concern per branch, open a PR. Never push to `main`. Agents never start release workflows.
3. New Swift files under `ios/Blith` are picked up because CI runs `xcodegen generate`. Never hand-edit the `.xcodeproj`.
4. Design rules (details in section 5): tokens only, status = colour + glyph + word, rust only for "outside your usual",
   mono labels ≥ 11 pt, readiness is a score out of 100 (never "%"), no medical claims, missing data never drawn as zero.
5. Honesty: the AI consent text must list exactly what leaves the phone (section 9).
6. Token economy: read only the lines you need; no extra screenshots or agents unless asked; PR check-ins every 6 hours.
7. The founder is the reviewer and merges. Keep PR descriptions plain: what changed, what is not yet verified.

## 2. What Blith is

A native SwiftUI iPhone app (iOS 18 target, Swift 5 mode) that turns Apple Health history into three daily scores
measured against the person's **own** usual range: **Readiness** (overnight HRV and resting heart rate plus sleep),
**Sleep performance**, **Load** (how much the day asked of the body). Plus overnight readings (resting HR, HRV,
respiratory rate, blood oxygen, wrist temperature), live heart rate, a free-rotating **3D body map** with dated notes,
and **Ask**, an assistant that computes from the person's records and answers with native cards.

| Path | What |
|---|---|
| `ios/Blith/App` | tabs (`BlithApp.swift`, `AppTab`), `AppRouter` (sheets, deep links) |
| `ios/Blith/DesignSystem` | `Theme.swift` (Palette, Typo, Space, Radius), `Components.swift`, `Instruments.swift`, `Horizon.swift` (after PR #12) |
| `ios/Blith/Features/*` | Today, Walk (= Activity), Sleep, Body, Ask, Scores, Detail, Onboarding, Profile |
| `ios/Blith/Charts` | `HealthCharts.swift`, `DayRibbon.swift` |
| `ios/BlithCore` | models, sync, store, analytics, insights, assistant tools, `BlithCLI`, tests (`swift test`) |
| `design/body3d` | generator for the 3D body (section 7) |
| `scripts/screenshots.sh` | CI simulator screenshots with demo data |

## 3. What has happened (history)

- v4 "Signal" design existed (blue, dark-first, five tabs: Today, Activity, Sleep, Body, Ask). Its CI screenshots
  predate the palette fix: they show green readiness and green/amber/red bars, which `DESIGN.md` forbids.
- An advisory review of the code found: Today has ten sections and no single story (live BPM and steps drawn bigger
  than readiness); without an Apple Watch the readiness hero is stuck on "0/14 Calibrating" forever; first run waits
  for up to five years of import and can show "0 steps"; "usual" means three different things; amber is overused;
  25 mono labels are under 11 pt; the AI consent text is inaccurate; the OpenRouter key is in Info.plist; the history
  JSON is not excluded from iCloud backup; a synthetic ECG beside live BPM is an App Review 1.4.1 risk.
- Design work (private claude.ai pages, section 11): widgets, a first redesign, then **Redesign 2**, a from-scratch
  look chosen by the founder: warm paper, ink and teal, **four tabs** (Today, Trends, Body, Ask), "horizon" bars
  instead of dials.
- **PR #10 (merged):** palette swap in `Theme.swift` (hex only, no renamed tokens).
- **PR #11 (merged):** this repo's `CLAUDE.md`, `/advisor`, `/qa`.
- **PR #12 (open, not compiled):** Today rebuilt, branch `redesign-2/today`. It has had an advisory review of every
  symbol; seven small findings were applied. **First job: get `ios-ci` green on it** (or fix what it reports).
- The founder asked for: the Organs layer on the body (section 7), Ask that can add a body note and log or fix an
  activity (section 8), a new icon set (section 10), and widgets (section 11).
- The repo may have moved: GitHub reports `pixelbuyte1/blith-health` while local remotes use `pixelbuyte/blith-health`.
  Ask the founder before changing remotes.

## 4. Build order

| # | Work | Notes |
|---|---|---|
| 0 | Get PR #12 green | Watch the `16b-nowatch` screenshot: it is the first render of the movement-hero Today. |
| 1 | Demo scenarios `iPhoneOnly`, `heartDeclined`, `emptyHealth` | `MockHealthProvider.swift` `DemoScenario`; add shots to `scripts/screenshots.sh`. Stop demo mode always faking live heart (TodayView). |
| 2 | First run | Show Today after the first 120 days import (`SyncEngine` already designs this; `AppModel` waits for all). Ask the Watch question first. "No steps yet", never "0 steps". |
| 3 | Trends tab (Activity + Sleep + HRV + RHR + Load) | One template: metric chips, period control, headline, chart on the usual band, 2–3 facts, rows. Keep Walk/Sleep screens until Trends covers them. |
| 4 | Four tabs | Today, Trends, Body, Ask in `BlithApp.swift`; keep deep links working (`AppRouter`, screenshot args). |
| 5 | Body: Organs layer | Section 7. |
| 6 | Ask: body notes and activity logging | Section 8. |
| 7 | Ask consent + server proxy + engineering fixes | Section 9. |
| 8 | Icons | Section 10. |
| 9 | Widgets | Section 11. |
| 10 | Retire dead code (`DayRibbon`, `RangeBar` if unused), update `DESIGN.md`/README screenshots | |

One PR per row, in this order. After each, ask the founder to run `ios-ci`.

## 5. Design: Redesign 2 (the target)

**Idea.** Four tabs. One shape for every score: the **horizon**, a 0–100 track with the person's usual range drawn as a
band and the value as a fill plus a crisp marker. One loud colour (rust) reserved for "outside your usual". Works
without a Watch. Honest states.

**Palette** (already in `Theme.swift` after PR #10; dark values second):
canvas EEF0EA/0E1211 · surface FBFBF8/161B1A · raised F2F3EE/1E2423 · sunken DADED6/262D2B · ink 14181B/EEF1EC ·
secondary ink 4A524F/A9B2AD · tertiary ink 6B736F/7E8883 · quiet BCC3BD/3A4340 · signal (teal) 0F6B6F/5EC4C0 ·
sleep indigo 4A4FA8/9EA3F2 · heart B83A35/F07A6E · note (rust) B8481A/F08A4B. Score band ramp: high 0F6B6F/5EC4C0,
moderate 4C8E90/3E8E8B, low A9C3C2/2A4E4C. Sleep stages stay one indigo ramp (deep darkest, REM lightest); awake is the
only warm stage. The mockups also try Onest and Martian Mono; **the app keeps Geist, Geist Mono and the New York serif**
(bundled). Do not add fonts without asking.

**Status grammar.** Always colour + glyph + word: High (up arrow), Moderate (minus), Low (down arrow); In your range
(check), Outside your usual (ring, rust), Learning (dots). "Below your usual" is neutral, never red. Rust is allowed for
(a) a reading outside the usual range and (b) the person's own body notes. Nothing else (not sample-data chips, not sync
freshness, not sleep debt).

**"Usual" has one meaning:** the middle half (25th–75th percentile) of the person's own readings over the last 60 days
(`Stats.usualRange` after PR #12). Needs 14 readings; until then show "Learning". Legends list only what a chart draws.

**Rules.** Mono labels never below 11 pt, caps, 0.8 tracking. Numerals scale with Dynamic Type except inside
instruments. Missing data (hollow) and a real zero (filled tick) never look alike. Loading is a breathing signal, not a
spinner. Reduce Motion replaces all motion. Copy: plain, specific, British spelling, sentence case, no exclamation marks,
no emoji, no words like "monitor", "abnormal", "warning", "diagnosis" except to disclaim ("isn't a diagnosis").

**Screens (Redesign 2).** Mockup pages in section 11.
- *Onboarding:* one question first, "Do you wear an Apple Watch to bed?" Yes (readiness, sleep, overnight readings, live
  heart; learns your usual over 14 nights) or iPhone only (steps, distance, walking metrics, Load; Today leads with
  movement). Then Connect (rows say why each type is read; heart is not "optional" if the person chose Watch), then
  Import ("Starting with your last 120 days", breathing signal, per-type progress, "Today is ready"; older years continue
  in the background).
- *Today (Watch):* header, Readiness hero (number, band, horizon with usual, one sentence, factor bars from the centre =
  usual: HRV 50%, resting HR 20%, sleep 30%, respiratory penalty only when outside usual), Sleep and Load tiles, Right now
  (live heart, steps vs usual by now), Worth a look, Overnight readings, More rows. **Built in PR #12.**
- *Today (iPhone only):* movement hero (steps vs usual by this hour on a band chart, "As usual/Above/Below"), How you
  walk (speed, step length on range bars), a card explaining that readiness and sleep need an Apple Watch.
- *Readiness detail:* pushed screen (not a sheet), big number, band, "What moved it", 30-day bars on the usual band with
  rings on unusual days, honest legend.
- *Trends:* metric chips, period control (D W M 6M Y), headline number, status, chart on the usual band, rows. Sleep
  inside Trends: last night hypnogram with stage totals, 14 nights vs need, 7-night debt in plain ink, bedtime tonight.
- *Body:* figure with Figure / Muscles / **Organs**, notes list (open and resolved), pins.
- *Ask:* conversation, native cards, always a line saying where an answer was made, composer. Consent sheet. New flows in
  section 8.
- *Profile:* milestones (6 of 10), data sources, Ask answers setting, units, delete all data. Demo scenarios hidden from
  real users.

## 6. Today as built (PR #12) — reference

Hero is exactly one of: `ReadinessHorizonCard` (score available), `CalibrationCard` ("Night n of 14", only when Watch data
exists), `MovementHeroCard` (no overnight heart data). Then `ScoreTile` ×2, `LiveHeartCard` (no ECG, `Palette.heart`),
Movement compact card (only if the hero isn't movement), Worth a look, Overnight readings, More. New pieces:
`HorizonBar`, `StatusLabel`, `RingGlyph` (`DesignSystem/Horizon.swift`), `TodayCards.swift`, `PaceStatus` (one ±10% rule
shared with Activity). Scroll ids `monitor`, `movement`, `live` still exist for the screenshot script.

## 7. Body: the organs layer

**Goal.** A third layer, **Organs**, next to Figure and Muscles. Tap the heart, lungs, liver, kidneys, stomach, brain,
etc.; see the readings Blith has that relate to it (heart: resting HR, HRV; lungs: respiratory rate, blood oxygen), with
the "for orientation, not diagnosis" line.

**Source (already in use).** Skin = BodyParts3D 4.0; muscles = Z-Anatomy `MuscularSystem100.fbx`. Z-Anatomy
(https://github.com/Z-Anatomy/Models-of-human-anatomy, the Blender file at https://github.com/Z-Anatomy/The-blend, and the
FBX exports the generator already uses from https://github.com/LluisV/Z-Anatomy) also ships organ, skeletal, vascular and
nervous systems. CC BY-SA 4.0; attribution already shown under the body map and in `design/body3d/LICENSE-ASSETS.md` and
`body3d.json`. Keep both. Share-alike: derived meshes stay CC BY-SA 4.0.

**How the generator works** (`design/body3d/build_body.py`, **pure Python, no Blender**: numpy, scipy, Pillow, pyfqmr; it
parses FBX itself via `fbxbin.py`). It downloads sources to `~/.cache/blith-body` (override `$BLITH_BODY_CACHE`), maps the
Z-Anatomy parts into the BodyParts3D frame with a similarity transform fitted once by ICP, pulls vertices that poke out of
the skin back under it, drops hidden parts by multi-view visibility, decimates to a triangle budget, writes
`ios/Blith/Resources/Body3D/body.bin` (~5 MB) and `body3d.json` (regions, named muscles, anchors, attribution). World
frame: metres, y up, feet at y = 0, facing +z, person's left at +x, 1.80 m tall. 33 BodyRegion labels per triangle.

**Steps.**
1. In a scratch checkout run `pip install numpy scipy Pillow pyfqmr` and `python3 design/body3d/build_body.py` once to
   confirm the current output reproduces (it should match the committed files; if the machine has no network to the
   sources, say so and stop).
2. List the FBX files in the Z-Anatomy repo's `Resources/Models/FBX` (do **not** assume names: confirm which file holds
   the visceral/organ systems and any cardiovascular and respiratory system files). Add them to the source table in the
   generator docstring.
3. Add an **organs layer** in `build_body.py` using the same ICP transform and visibility logic as muscles, but without the
   skin-snapping step (organs sit inside the torso): group triangles per named organ (heart, left/right lung, liver,
   stomach, left/right kidney, brain, spleen, pancreas, intestines), decimate to a modest budget (target body.bin under
   about 8 MB total; tell the founder if it grows more), and write per-organ metadata into `body3d.json` (`organs`: id,
   display name, anatomical name, vertex/triangle ranges, anchor point, related metrics).
4. Extend the binary format only additively; keep the loader backward compatible. Check how `Body3D.swift` parses
   `body.bin` (header, groups) and extend it the same way muscles were added.
5. UI (`BodyView.swift`): the segmented control becomes Figure / Muscles / Organs; in Organs the skin is a faint
   see-through shell (low alpha), organs are lit with the same imaging-chamber lighting; tap selects an organ (reuse the
   region-tap machinery), shows a panel (organ name, related readings from `HealthSnapshot`, status glyph + word, one
   plain sentence). Heart and lungs may pulse very subtly only if Reduce Motion is off.
6. **Performance:** `Body3D` currently renders at 60 fps with HDR, bloom, SSAO and 4× MSAA and parses a 5 MB mesh on the
   main thread. Move parsing off the main actor and cap frame rate when idle before adding more geometry.
7. Rerun `design/body3d` previews (`preview-*.png`) and add an organs preview. Commit generated files in their own commit.
8. Update the "Z-Anatomy" credit line if the organ source files differ.

Honesty: label it "for orientation and notes, not diagnosis"; never colour an organ red/green by health.

## 8. Ask: add a body note and log or fix an activity

Today Ask's tools are deterministic and read from the snapshot (`HealthAssistantTools.swift`: 17 tools plus
`show_widget`; `AssistantBlock` + `ChatBlockView` render native cards). The model never produces numbers or UI. Keep that.
Verify the exact tool schema format there before extending.

**A. "I sprained my ankle yesterday" → body note.** New tool `propose_body_note` (read-only, returns a *proposal*):
args `region` (one of the 33 `BodyRegion`s, with side), `text`, `date` (resolved to a calendar date by app code, not the
model), `status` (open/resolved). If the side or region is unclear the assistant asks one short question with chips
("Right ankle" / "Left ankle"). Result is a new block type `bodyNoteProposal` rendering a card: mini body with the region
marked, title, date, **Edit** and **Add note**. Nothing is saved until the person taps **Add note**; that calls the
existing body-note store. Show the safety line ("Blith can't assess injuries…"). Existing `body_note` card shows saved
notes ("Show my body notes").

*Status (Oct 2026):* A is built in its own PR: `propose_body_note`, the `bodyNoteProposal` card (Edit reuses
`BodyNoteEditor`, Add note calls `AppModel.saveNote`), and on-device parsing in `LocalAssistant` (`BodyRegion.match`).
Not yet: the mini body figure on the card, and chips for the side (Ask asks in words).

**B. "I walked 2 miles today outdoors between 4:30 and 5:20" → workout.** New tool `propose_activity` returning a
proposal: `kind` (walk/run/hike/cycle…), `start`, `end` (parsed in app code from the person's words in local time),
`distance` (mi or km per units), derived duration and pace, `indoor/outdoor`. Block `activityProposal` with **Edit**
(date, times, distance, type) and **Save to Health**. Never save without the tap. **Fixing** an existing entry works the
same way: tool `find_activity` (by date and time window) → proposal showing before/after → confirm.

**HealthKit write correction (important).** The app is currently read-only: `AppleHealthProvider.requestAuthorization`
passes `toShare: Set<HKSampleType>()`, and `NSHealthUpdateUsageDescription` in `ios/project.yml` says "Blith doesn't save
anything to Apple Health." Saving workouts needs: request share authorization for `HKObjectType.workoutType()` (and
distance types, e.g. `distanceWalkingRunning`) at the moment the person first taps **Save to Health**, not at launch;
rewrite `NSHealthUpdateUsageDescription` truthfully ("Blith saves workouts you add yourself, such as a walk you describe
to Ask. It never writes anything else."); build the sample with `HKWorkoutBuilder`/`HKWorkout` source metadata
`"Added in Blith"` (`HKMetadataKeyWasUserEntered = true`) so it never looks like a Watch recording; update `docs/PRIVACY.md`.
Editing or deleting is only possible for samples Blith itself saved (HealthKit rule); for other apps' entries, say so.
After saving, trigger a sync so steps, Load and Today refresh. Check Apple's current HealthKit docs for the exact
authorization and builder calls before writing them.

**Local-only fallback.** When answers are on-device (no consent), parsing must still work for these two flows (simple
patterns for body parts, dates, times, distances) or Ask says it needs cloud answers.

## 9. Ask consent, privacy and engineering debt

- **Consent copy must be accurate.** Tools send up to 120 dated values per metric, body-note text, blood oxygen and wrist
  temperature when relevant, device names such as "Zen's Apple Watch" (can contain the name), and the last 8 chat turns,
  to OpenRouter and then the model provider. Blith doesn't store it and doesn't control provider retention. Buttons: "Use
  cloud answers" / "Keep answers on this iPhone". Mockup in the Redesign 2 page. Fix `AskView.swift` `AIConsentSheet` and
  `docs/PRIVACY.md` (it also omits blood oxygen, respiratory rate, wrist temperature, VO₂ max; and says conversations are
  stored, but they live in memory only).
- **OpenRouter key is in Info.plist** (`project.yml`, `codemagic.yaml`) and can be extracted from the IPA. Needs a small
  server proxy with a per-install token and a no-retention setting on the request. Needs the founder's decision on where
  to host it. Do not invent a host.
- **History file in iCloud backup.** `LocalHealthStore` writes file-protected JSON but doesn't exclude it from backup,
  while `docs/RELEASE.md` says it's not in iCloud. Set `isExcludedFromBackup` or correct the doc.
- Analytics recomputed in view bodies on the main thread (SleepView, WalkView, ScoreViews, HealthCharts); `Body3D` cost;
  navigation is sheets-only with a 350 ms sleep chain (`BlithApp.swift`); app target is Swift 5 mode.
- App Review: QA demo scenarios visible in Profile and "Huawei… will appear" (promises an unbuilt feature); keep health
  claims out; privacy manifest must list every health type read.

## 10. Icons

Tab icons are custom template SVGs in `ios/Blith/Resources/Assets.xcassets/Symbols` (24 pt grid; `.fill` variants exist
but are unused). For four tabs you need Today, Trends, Body, Ask (selected = fill variant). Plan: the founder is
generating a set with ChatGPT; accept SVG or PDF, 24×24 grid with 2 px padding, 2 px stroke, round caps, template
rendering, and a filled variant for selected. Body icon prompt used:
"A single iOS tab-bar icon for 'Body': simple friendly standing figure from the front, arms slightly away from the body,
one continuous outline with round caps, a small heart inside the chest; SF Symbols style, 2 px stroke on a 24×24 grid,
no fill except the small heart, no face details, black on white and white on black, plus a filled selected variant, flat,
no gradients, shadows or text." The other three icons reuse the same prompt with a different subject
(Today: a ring with a centre dot; Trends: a line chart with a band behind it; Ask: a speech bubble with a spark).
Also check `design/symbols-preview.html` and keep `Symbols` previews updated. App icon (`design/app-icon*.svg`) is unchanged.

## 11. Mockups and widgets

Private claude.ai pages (the founder can share screenshots; they open only for the founder's account):
- **Redesign 2 (the target; 13 screens):** https://claude.ai/artifact/KiSzZBS1DhP45KxfpjZdgY
- Redesign 1 (reviewed direction, superseded): https://claude.ai/artifact/DEY2TaG4HSdaL3hX4Kcobt
- Blith widgets (Signal look; recolour to Redesign 2): https://claude.ai/artifact/JKCSbC2HSbTXfitxq3X5AR

**Widgets (not built).** WidgetKit extension `BlithWidgets` with an App Group (`group.<bundle id>`), mirroring
Skintel's approach: `Shared/` Foundation-only snapshot written by the app after each Health sync, timelines reloaded then;
widgets never read HealthKit (it's unreadable while locked). Sizes: Readiness (small), Readiness + three factors (medium),
Sleep (small), Overnight reading (small), Today (large); Lock Screen circular ×2, rectangular, inline. **No live heart rate
widget** (widgets refresh a few times an hour). Snapshot (scores and ranges only, no raw samples): asOf, readiness
{score, band, usual}, factors {hrv, restingHR, asleepMin with usual and need}, sleep {score, bed, wake, stages}, load
{value, dayUsual}, week[7], monitor {inRange, of, flagged}. Tinted/Clear: mark arcs and bars `widgetAccentable()`.
Privacy: lock-screen values `privacySensitive`. Use the Redesign 2 palette and Geist (bundle fonts in the extension).

## 12. Sample data (the demo person "Zen", Tue 29 Sep, 15:30)

Readiness 71 High (high ≥ 67, moderate ≥ 34), usual 55–80; last 7 days W T F S S M T = 82 55 68 71 32 91 71 (avg 67).
Sleep 88%: asleep 8h 24m, need 7h 37m, in bed 8h 51m, efficiency 95%, 7-night debt 5h 22m; stages awake 27m, REM 2h 20m,
core 4h 36m, deep 1h 28m. Load 2.5 of 10 so far, usual 3.8–4.7 by day's end. Steps 2,883 by 15:30 vs usual 2,948;
7-day avg 6,902; four weekly averages 5,405 → 6,020 → 6,610 → 7,011 (+30%). Overnight: resting HR 57 (usual 57–61),
HRV 46 ms (36–57), respiratory 14.3 (14.0–15.2), SpO₂ 96.8% (95.4–97.8), wrist temp 35.99 °C (35.72–36.17). Live heart
74 bpm (Warm; resting 57). VO₂ ≈ 42.5. Body notes: left knee stiff on stairs (20 Sep, open), rolled right ankle (20 Aug,
resolved), lower back tight (2 May). Milestones 6 of 10. Check-in streak 1.

## 13. Verification checklist (every PR)

1. Grep-check every symbol you touch; re-read the diff as a compiler would.
2. `cd ios/BlithCore && swift test` if core changed (needs a Swift toolchain; say so if unavailable).
3. New files are under `ios/Blith`; `project.yml` changes only when really needed.
4. `scripts/screenshots.sh` covers the new state (add a shot) so CI renders it in dark and light.
5. Ask the founder to run Codemagic `ios-ci` on the branch; fix what it reports; never skip a failing test.
6. PR body: what changed, what is not verified, what you left.

## 14. Open decisions for the founder

- Repo address (pixelbuyte vs pixelbuyte1).
- Where to host the OpenRouter proxy.
- Keep Geist (recommended) or adopt the mockup fonts.
- Whether Trends replaces Activity and Sleep immediately or alongside them for one release.
- Whether Ask may write to Apple Health at all (needs the permission and App Review explanation in section 8).
