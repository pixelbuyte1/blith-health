# Blith chat icons (DRAFT)

Work in progress for the Ask chat screen. **Do not wire these into the app yet.** More icons are still to
come from the founder, who will also ask for fixes to these. Wait for the final set before converting anything.

## What is here
| File | Icon | Notes |
|---|---|---|
| `sheet-draft.png` | First 12-icon sheet (send, mic, new chat, assistant, log activity, save to Health, sleep, readiness, heart rate, body, suggestion, history) | Reference only |
| `send.png` | Send | Reads as "sign in / enter" (arrow into a box). Likely needs a redraw as a paper-plane or up-arrow |
| `mic.png` | Microphone | Good as is |
| `new-chat.png` | New chat | Speech bubble with a teal plus; the bubble outline has gaps around the plus |
| `assistant.png` | Assistant avatar | Heartbeat line in a circle |

## Style (match this for every new icon)
- Thin monoline outline, rounded caps and joins, about 1.75 px stroke on a 24 px grid, no fills, gradients or shadows.
- Ink strokes, at most one teal element per icon. Never rust (`Palette.note` is reserved for out-of-range readings and
  the person's own notes), no red or orange.
- Single-colour in the app: they get tinted by `Palette` tokens, so no hex literals outside `Theme.swift`.

## Rules for agents
1. These are raster drafts (PNG). The app needs vector (SVG or PDF) in an asset catalog, one image set per icon.
   Convert only after the founder approves a final set.
2. Do not run CI or a simulator to look at them. Show how a screen looks with an HTML mockup instead (see `CLAUDE.md`).
3. Copy rules still apply: no medical claims, and the Save to Health icon never implies anything is saved
   without the person tapping Save.
