# Gaitway

A watch-first walk/run app. (The repo, Xcode targets and bundle
identifiers keep their original `FunRun` names — the App Store Connect
record for Gaitway is bound to `com.paulrobinson.FunRun`, and bundle IDs
are forever. Only user-facing names say Gaitway.) Start a session on your Apple Watch and just
move — the app works out whether you're walking or running, pauses itself
when you stop, and asks how hard it felt when you finish. The iPhone app is
the companion: register your trainers there, track their wear, and browse
your history.

## What it does

- **Auto walk/run detection** — cadence (steps per minute) is the primary
  signal, speed the fallback. A gait change has to hold for ~6 seconds
  before the mode flips, so crossing a road at a jog doesn't bounce the
  display. The walk/run split is saved as segments on every run. What
  speed counts as running is yours to set — "Run pace" on the watch's
  start screen, default 9 km/h (≈6'40"/km) — since one runner's easy jog
  is another's sprint.
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
  perceived effort: separate walking and running questions when the
  outing saved both kinds of workout, each defaulting to your last
  answer for that mode. On watchOS 11+ each workout in the chain gets
  the score for its own mode, so the Fitness app rates the session
  correctly too.
- **Trainer wear tracking** — register shoes on the phone, pick a pair on
  the watch when starting, and each synced run adds its distance to that
  pair, with a wear bar and replacement warning.
- **Fork pop-ups** — the watch records each session's GPS track and
  learns where your routes fork (a fork is where passes that shared a
  corridor genuinely part ways, detected by path divergence — so
  zigzags, GPS drift and out-and-backs never fake one). About 100 m
  before a known fork, a wrist tap and pop-up price each choice —
  left/right/straight relative to your heading — with the length of the
  segment it leads onto, your fastest pace over it in the last 28 days
  (the time to beat), the quickest known time home going that way
  (your best time on each leg of the fastest route, chained), and how
  often you go that way. Swipe right mid-run for the full forks page.
- **Fitness app maps** — every saved workout gets its GPS route attached
  (each chained walk/run workout gets its slice), so the Fitness app
  draws the map. The phone's run detail shows the route too, start and
  finish marked.
- **Kilometre splits** — each km taps the wrist and flashes the split's
  moving time with a delta against your own recent history over the
  same ground: each tick on known ground compares time spent with what
  your usual local pace predicts, and unknown ground contributes
  nothing — so a detour never fakes a good or bad kilometre.
- **Watch complication** — the Gaitway logo on the watch face, one tap
  from opening the app and starting a run.
- **Shoe notifications & default pair** — the phone notifies when a pair
  crosses 90% and 100% of its replacement distance, and the watch
  remembers your last-used pair so forgetting to pick doesn't lose wear
  tracking.
- **Training load** — the phone's history leads with this week's
  distance and session-RPE load (effort × minutes), compared to your
  4-week average with a gentle warning when the ramp exceeds +40%.
- **Take me home** — one tap on the controls screen and the wrist shows
  the first turn of the fastest known way back to your usual finishing
  spot (learned from where runs end), with the ETA; between forks it
  falls back to a plain arrow toward home.
- **The network map** — a phone tab that draws everything the watch has
  learned: your run network on a map as a joined-up web — one coloured
  line per unique physical stretch, pinned to its fork dots — updating
  as runs land. Runs cluster by where they start — home, holidays,
  wherever — into separate networks with geocoded names, switchable
  from the globe menu. Before forks exist it shows your raw tracks, so
  the map is never empty.
- **Route backup** — every recorded route mirrors to the phone over
  WatchConnectivity file transfers, where standard iPhone/iCloud backups
  cover it. A watch with empty history (new watch, reset) automatically
  asks the phone to send everything back, favourites and names included.
- **Segments, raced live** — the stretch between two forks is a
  segment. While you run one, the stats and forks pages carry a status
  row: distance left of the segment (its length inferred from history
  once ~40 m identifies the branch) and a live ± against your usual
  self over that exact ground. Completing a segment flashes your time
  with a signed delta against your last 28 days on the same stretch
  (green faster, red slower), and a medal when you beat every recent
  pass. The 28-day window keeps comparisons honest about current
  fitness; the fork map itself uses all stored history.

## Project layout

| Folder | Target | What's in it |
| --- | --- | --- |
| `WatchApp/` | FunRunWatch (watchOS) | Workout session, auto-detection, auto-pause, live metrics, effort prompt, route intelligence |
| `WatchWidget/` | FunRunWidgetExtension (watchOS) | Watch-face complication (app launcher) |
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
- Fork detection snaps tracks to an ~18 m grid (`RouteGraph`) and finds
  forks by path divergence: every pair of run paths (each against
  itself too, which finds loop mouths) is walked with a together/apart
  state machine, and a fork is the last shared cell before two passes
  part ways or the first where separate corridors merge. Guards keep
  zigzags, GPS drift, out-and-back tips and run start/stops from faking
  one. Route history lives on the watch — 12 months, capped at 400
  runs — as one file per run plus a small index (`RouteHistoryStore`),
  so launch stays light; the route graph is built off the main actor at
  session start and predictions switch on when it's ready.
- Requires an Apple Watch with GPS; permissions requested on first start:
  Health, Motion & Fitness, Location.

## Website

The Gaitway site at
[gaitway.robbo-online.uk](https://gaitway.robbo-online.uk) lives
in `docs/` and deploys via GitHub Actions
(`.github/workflows/pages.yml`) on every push to `main` that touches it.
The brand comes from `docs/applogo.png` — near-black, electric cyan and
hot magenta — and the same artwork feeds the iOS and watchOS app icons,
the phone launch screen, the watch start screen and the complication.

## Demo mode (screenshots)

Launch either app with the `-demo` argument (Product → Scheme → Edit
Scheme → Arguments) and it presents seeded example data: three trainers
at varied wear, three weeks of runs with map loops and a chained
walk/run/walk outing on the phone; demo shoes on the watch start screen
plus frozen mid-run scenes (live stats with the segment row, the fork
pop-up, the km-split pop-up) as further pages. Strictly in-memory and
debug-only — nothing is persisted, synced, or written to HealthKit, and
release builds compile the flag to false.

## Building

Open `FunRun.xcodeproj`, pick the `FunRun` scheme for the phone app or
`FunRunWatch` for the watch app, and run. Both targets sign automatically
with the same team as ItsJustAGame.
