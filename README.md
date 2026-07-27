# FunRun

A watch-first walk/run app. Start a session on your Apple Watch and just
move — the app works out whether you're walking or running, pauses itself
when you stop, and asks how hard it felt when you finish. The iPhone app is
the companion: register your trainers there, track their wear, and browse
your history.

## What it does

- **Auto walk/run detection** — cadence (steps per minute) is the primary
  signal, speed the fallback. A gait change has to hold for ~6 seconds
  before the mode flips, so crossing a road at a jog doesn't bounce the
  display. The walk/run split is saved as segments on every run.
- **Watch-first** — the whole workout runs on the watch as a HealthKit
  workout session (heart rate from the wrist, GPS-calibrated distance),
  and works even if the phone stays in a pocket or at home.
- **Live metrics on the wrist** — current pace, distance so far, heart
  rate, elapsed time, plus what the app currently thinks you're doing.
- **Auto-pause after 5 seconds** — stand still for 5 seconds and the
  session pauses; start moving again and it resumes on its own. Manual
  pause never auto-resumes.
- **Chained workouts on finish** — a mixed outing is saved to HealthKit
  as separate, correctly-typed workouts: walk 2 km, run 5 km, walk 4 km
  becomes three workouts back-to-back. A shortest-time gate (5 minutes)
  stops token efforts from splitting the session — walk 1 km, run 500 m,
  walk 2.5 km just saves as one 4 km walk. Each chunk carries its own
  slice of the heart-rate stream, its distance and energy share, and any
  pauses that fell inside it.
- **Effort score on finish** — after saving, the watch asks for a 1–10
  perceived effort. On watchOS 11+ the score is stored as the effort
  score on every workout in the chain, so the Fitness app rates the
  session correctly too.
- **Trainer wear tracking** — register shoes on the phone, pick a pair on
  the watch when starting, and each synced run adds its distance to that
  pair, with a wear bar and replacement warning.

## Project layout

| Folder | Target | What's in it |
| --- | --- | --- |
| `WatchApp/` | FunRunWatch (watchOS) | Workout session, auto-detection, auto-pause, live metrics, effort prompt |
| `FunRun/` | FunRun (iOS) | Shoe registry and wear, run history, watch sync |
| `Shared/` | both | Models (`Shoe`, `RunSummary`, `ActivityMode`), sync codec, formatters |
| `Config/` | — | Info.plists and HealthKit entitlements |

Phone ↔ watch traffic uses WatchConnectivity: the shoe list travels
phone → watch as application context (latest state wins), finished runs
travel watch → phone as queued user-info transfers, so nothing is lost if
one side is asleep.

## Notes

- The sensors run as a single live HealthKit session for the whole
  outing (continuous heart rate, GPS distance). At the end the detected
  segments are gated and merged (`WorkoutChunker`); a pure run keeps the
  live workout with its full-fidelity data, anything else is rewritten as
  one workout per chunk and the live workout is discarded. If a chunk
  save fails, the partial saves are rolled back and the whole session is
  kept as a single workout — a run is never lost.
- The effort-score HealthKit sample needs watchOS 11; on older versions
  the score still syncs to the phone and shows in history.
- Requires an Apple Watch with GPS; permissions requested on first start:
  Health, Motion & Fitness, Location.

## Building

Open `FunRun.xcodeproj`, pick the `FunRun` scheme for the phone app or
`FunRunWatch` for the watch app, and run. Both targets sign automatically
with the same team as ItsJustAGame.
