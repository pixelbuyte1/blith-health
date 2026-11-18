# Blith privacy policy

_Last updated: October 3, 2026_

Blith helps you understand your own health data. This policy explains what the app reads,
where it is kept, and what (if anything) leaves your iPhone.

## What Blith reads

With your permission, Blith reads from Apple Health only the categories you choose:

- **Movement:** steps, walking + running distance, active energy, exercise minutes, flights
  climbed, walking speed, step length, walking asymmetry, double support time, workouts.
- **Sleep:** sleep analysis (time asleep and stages).
- **Body:** weight, body fat percentage.
- **Vitals:** blood oxygen, respiratory rate, wrist temperature during sleep, VO₂ max.
- **Heart:** resting heart rate, walking heart rate average, heart rate variability, and heart rate readings (shown live on Today; only the last 24 hours are held in memory and nothing new is stored for them).

Blith writes to Apple Health only when you save a walk you recorded with GPS in Blith: one
walking workout with its pauses, the distance measured along good GPS, and the route. It never
writes steps or active energy (your iPhone and Apple Watch already record those), and if your
Apple Watch already recorded the same walk, Blith keeps the Watch's walk and writes nothing.
Blith asks for this permission the first time you save a walk. You can review or revoke access
at any time in **Settings › Health › Data Access & Devices › Blith**.

## Location and motion (walks)

Blith uses your location only while you record a walk, including with the screen locked (iOS
shows a blue location indicator while it does). It uses the iPhone's motion sensor for steps and
the barometer for climb during the walk. The route stays on your iPhone and, when you save the
walk, in Apple Health. It is never sent to the AI assistant or anywhere else.

## Where your data is stored

Your imported history, settings, body notes and recorded walks are stored **on your iPhone**, in the app's
private storage, encrypted by iOS while your device is locked. Ask conversations are kept
in memory only and are gone when you close the app. There are no Blith accounts
and no Blith servers holding your health data.

## The AI assistant (optional)

Ask can answer questions in two ways:

1. **On this iPhone** (default until you choose): answers are computed locally.
2. **With AI**, only if you turn it on: your question, the last few messages of the chat, and
   the readings needed to answer it are sent through OpenRouter (openrouter.ai) to the AI model
   provider, which writes the answer. Readings can include daily or weekly values (up to 120 per
   measure), sleep, heart and body readings, your body notes, and the name of the device that
   recorded them (an Apple Watch name may contain your name).
   - Never sent: your location, contacts or Apple ID.
   - Blith doesn't control how long OpenRouter or the model provider keep requests; see their
     privacy policies.
   - Not used by Blith for advertising or profiling.
   - You can switch this off at any time in **Profile › AI assistant**.

## What Blith does not do

- No advertising, no tracking, no analytics SDKs, no selling or sharing of data.
- Health data is never used for marketing.

## Deleting your data

**Profile › Delete all Blith data** removes everything Blith stored. It does not change
anything in Apple Health. Deleting the app also removes all of its data.

## Medical disclaimer

Blith describes patterns in your own data. It is not a medical device and does not diagnose,
treat or prevent any condition. For symptoms or health concerns, talk to a clinician; in an
emergency, contact your local emergency number.

## Contact

Questions: open an issue at https://github.com/pixelbuyte/blith-health.
