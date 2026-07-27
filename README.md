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
- **Intersection predictions** — the watch records each session's GPS
  track and learns where your routes fork. Reaching a known decision
  point taps your wrist and shows each choice — left/right/straight
  relative to your heading — with the expected time until you're back,
  the predicted session-total calories, and how often you've gone that
  way. Because each branch's numbers are the average of what *actually*
  happened on past runs that took it, later forks are automatically
  priced in probabilistically: if the left turn sometimes becomes a
  25-minute loop and sometimes a 40-minute one, you see the
  frequency-weighted expectation, and it sharpens as history grows.
- **Favourite routes** — swipe any route in the ghost picker to star and
  name it ("Canal loop"). Favourites sit at the top of the picker, show
  their name everywhere, and are exempt from the 12-month cleanup, so a
  named route never ages out. Swipe a favourite to rename or unstar it.
  Racing a favourite automatically races your **fastest recorded
  attempt** of that route (matched by distance and track overlap) — a
  favourite means the route, not one day's run.
- **Fitness app maps** — every saved workout gets its GPS route attached
  (each chained walk/run workout gets its slice), so the Fitness app
  draws the map. The phone's run detail shows the route too, start and
  finish marked.
- **Kilometre splits** — each km taps the wrist and flashes the split's
  moving time with its delta to the previous kilometre.
- **Pace-adjusted predictions** — intersection and next-fork times are
  scaled by how today compares to your historical average pace, clamped
  so one bad kilometre doesn't distort the forecast. A slow day honestly
  predicts a slower finish.
- **Watch complication** — this week's distance on the watch face; tap
  to open the app and start. Requires the `group.com.paulrobinson.FunRun`
  app group (automatic signing creates it on first build).
- **Shoe notifications & default pair** — the phone notifies when a pair
  crosses 90% and 100% of its replacement distance, and the watch
  remembers your last-used pair so forgetting to pick doesn't lose wear
  tracking.
- **Training load** — the phone's history leads with this week's
  distance and session-RPE load (effort × minutes), compared to your
  4-week average with a gentle warning when the ramp exceeds +40%.
- **Ghost runs** — pick any route from the last 12 months and replay
  it against a ghost of yourself. On route, the wrist shows the upcoming
  turn, whether you're ahead or behind the ghost at this exact spot
  (green/red seconds), and the distance left — covering both "I don't
  know where I'm going today" (just follow the arrows) and "I want to do
  this route" (race it). Drift off the route and it flips to
  find-my-way-back mode: an arrow to the nearest point of the route and
  how far away it is, with a haptic when you lose the route and another
  when you rejoin — for the "I don't know where I am" moments. Matching
  is monotonic along the ghost's track, so out-and-back routes don't
  snap you onto the homeward leg while you're still outbound.
- **Segment comparisons** — the stretch between two decision points is a
  segment. Completing one flashes your time with a signed delta against
  your last 28 days on that same stretch (green faster, red slower), and
  a medal when you beat every recent pass. At a fork, each branch also
  quotes the expected time to the next fork. The 28-day window keeps
  comparisons honest about current fitness; the decision-point map
  itself uses all stored history.

## Project layout

| Folder | Target | What's in it |
| --- | --- | --- |
| `WatchApp/` | FunRunWatch (watchOS) | Workout session, auto-detection, auto-pause, live metrics, effort prompt, routes/ghosts |
| `WatchWidget/` | FunRunWidgetExtension (watchOS) | Watch-face complication (weekly distance) |
| `FunRun/` | FunRun (iOS) | Shoe registry and wear, run history, maps, training load, watch sync |
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
- Intersection detection snaps tracks to an ~18 m grid (`RouteGraph`); a
  cell is a decision point when past traversals — arriving on a similar
  heading — leave in two or more direction clusters with at least two
  runs each. Predictions therefore need a couple of passes over each
  branch before they appear. Route history lives on the watch — 12
  months, capped at 400 runs — as one file per run plus a small index
  (`RouteHistoryStore`), so launch stays light; the route graph is built
  off the main actor at session start and predictions switch on when
  it's ready.
- Requires an Apple Watch with GPS; permissions requested on first start:
  Health, Motion & Fitness, Location.

## Building

Open `FunRun.xcodeproj`, pick the `FunRun` scheme for the phone app or
`FunRunWatch` for the watch app, and run. Both targets sign automatically
with the same team as ItsJustAGame.
