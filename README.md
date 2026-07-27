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
- **Workout + effort score on finish** — the session is saved to
  HealthKit as an outdoor run, then the watch asks for a 1–10 perceived
  effort. On watchOS 11+ the score is stored as the workout's effort
  score, so the Fitness app rates the session correctly too.
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

- HealthKit can't switch a workout's activity type mid-session, so mixed
  sessions are saved as outdoor runs; the walk/run split lives in the
  app's own segment data.
- The effort-score HealthKit sample needs watchOS 11; on older versions
  the score still syncs to the phone and shows in history.
- Requires an Apple Watch with GPS; permissions requested on first start:
  Health, Motion & Fitness, Location.

## Building

Open `FunRun.xcodeproj`, pick the `FunRun` scheme for the phone app or
`FunRunWatch` for the watch app, and run. Both targets sign automatically
with the same team as ItsJustAGame.
