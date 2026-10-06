# Blith 2.0 — design mockup

Design-only. No Swift has changed yet. The live canvas is https://claude.ai/artifact/8Mopot9gPUq9NcYbegoWGR
(private to the founder). These files are its source: one `.dc.html` per artboard plus `canvas.json`.
They need the canvas runtime and do not open on their own.

## Direction

- **Dark first, with a real light mode.** The neutrals are near-black blue-grey, and the light mode is warm paper,
  not an inversion.
- **Colour carries meaning.** Three status hues, used only for readiness:
  - Primed: teal
  - Steady: amber
  - Strained: coral red

  Three signal hues:
  - Load: blue
  - Sleep: periwinkle
  - Vitals: cyan

  Everything else is ink.
- **Status is a word, a glyph and a number.** A glyph is ▲, ■ or ▼. Readiness is never a percentage. Being above
  or below your usual is said plainly, in neutral ink.
- **No gauges or rings.** Data uses three shapes:
  - Range bars: your usual as a band, today as a marker.
  - Band and line, for trends.
  - Bars from zero.

  Missing data is hollow and a true zero is a stub, so they never look alike.
- **One story per screen.** Today has one hero (readiness), one action line, what's behind it, load and context
  tags. Trends, Sleep, Body and Ask each lead with a single number or answer.
- **Glass only where it floats.** That means the tab bar and the Ask composer.
- **Motion once.** Numbers roll once and charts draw once. Nothing glows or pulses.

## Tokens

| Role | Dark | Light |
|---|---|---|
| Base | #0C1014 | #F4F2EE |
| Surface | #131920 | #FFFFFF |
| Raised | #1A222B | #ECE9E3 |
| Text 1 / 2 / 3 | #F1F4F6 / #A9B4BF / #97A3AF | #12171B / #4B5762 / #5F6B76 |
| Primary action | #D9CDB8 (ink #0C1014) | #12171B (ink #F4F2EE) |
| Primed / Steady / Strained | #3FD0B0 / #F2B53E / #F0545E | #077A67 / #946000 / #C4283C |
| Load / Sleep / Vitals | #4DA3F7 / #8C9BF0 / #7CCBE6 | #0B63C5 / #4F5FC4 / #16708F |
| Sleep stages deep / core / REM | #4F67BD / #7F95E3 / #B5C4F5 | #34489A / #5F78D6 / #9FB2EE |
| Usual band | Text 2 at ~17% | Text 2 at ~13% |

Awake is drawn as a hollow outline, never a fill.

## Type

The app uses SF Pro and the mockup uses Archivo as a web stand-in:

- **Hero numerals:** condensed bold tabular, 96–124 pt. In SwiftUI: `.width(.condensed)`, `.bold()`, `.monospacedDigit()`.
- **Large title:** 34 Bold.
- **Body:** 17 Regular.
- **Labels:** 12 Semibold caps with +9% tracking.
- **Weights:** no Light weights.

## Screens

- `Main.dc.html`: Today
- `Trends.dc.html`: Trends
- `Sleep.dc.html`: Sleep
- `Body.dc.html`: Body
- `Ask.dc.html`: Ask
- `TodayLight.dc.html`: Today in light mode
- `System.dc.html`: tokens and patterns

Every screen has a `theme` tweak (dark or light), and the tab bars link the screens together.

All numbers are sample data.
