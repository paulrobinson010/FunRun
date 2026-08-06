# App Store Connect metadata

Copy-paste ready. Character counts verified against Apple's limits —
re-run `python3 appstore/check_lengths.py` after any edit.

---

## Name (30)

    Gaitway

## Subtitle (30)

    Knows your walk from your run

Alternatives, both within limit: `The watch-first walk/run app`,
`Auto walk/run. Learns routes.`

## Promotional text (170)

Shown above the description; can be changed any time without a new
build, so use it for whatever's newest.

    Build a route from your own network on the phone, send it to your wrist, and follow it turn by turn — with distance to go and how you're doing against yourself, live.

## Keywords (100, comma-separated, no spaces)

    walk,run,run-walk,intervals,pace,splits,route,gps,segment,shoe,mileage,trainers,cadence,tracker

Deliberately excludes "Gaitway" (the name is indexed separately),
"Apple Watch" (Apple's trademark; rejected in keywords), and any
competitor's name.

## Description (4000)

    Gaitway is a walk/run app that lives on your wrist. Start it and go — it works out whether you're walking or running from your step cadence, pauses itself when you stop, and asks how hard it felt when you finish.

    Then it starts learning where you run.

    AUTOMATIC WALK/RUN DETECTION
    Step cadence tells walking from running — a gait change, not just a speed change. A mixed outing is saved to Health as separate, correctly-typed workouts: walk 2 km, run 5 km, walk 4 km becomes three workouts back to back, while a token 500 m jog just stays part of the walk. What pace counts as running is yours to set.

    AUTO-PAUSE IN FIVE SECONDS
    Stand still for five seconds and the session pauses itself. Start moving and it resumes on its own. Manual pauses stay paused until you say otherwise.

    FORKS, PRICED
    Every run teaches Gaitway your local map. About 50 m before a junction you've run before, your wrist shows each way on: how long that stretch is, your fastest pace over it in the last 28 days — the time to beat — and the quickest you could be home going that way.

    SEGMENTS, RACED
    The stretch between two forks is a segment. While you run one, your watch carries the distance still to go and a live plus/minus against your own recent history over that exact ground. Finish it and see your time against your last 28 days, with a medal when you beat every recent pass.

    KILOMETRE SPLITS THAT MEAN SOMETHING
    Each kilometre taps your wrist with its time and a delta against your usual self over the same ground. Ground you've never run counts as neutral, so a detour never fakes a good or bad split.

    YOUR NETWORK, MAPPED
    The iPhone app draws everywhere you run as a connected web of segments and junctions — one line per stretch, however many times you've run it. Tap any segment to see how often you've run it in each direction and your best time each way.

    PLAN A ROUTE, THEN RUN IT
    Build a route on your phone by picking segments from your own network. Each choice shows its length, its typical time, and the shortest way back to the start — or tells you it finishes back home. Send the route to your watch and your next workout follows it turn by turn, with distance to go and an overall plus/minus.

    TAKE ME HOME
    One tap mid-run and your wrist shows the fastest known way back to where your runs usually finish.

    TRAINER WEAR
    Register your shoes on the phone, pick a pair on the watch, and every kilometre counts against them — with a nudge at 90% of their life and a warning when they're done.

    TRAINING LOAD
    Your effort scores earn their keep: this week's load against your four-week average, with an easy-does-it warning when you're ramping too fast.

    ON YOUR WATCH FACE
    A complication that's one tap from starting a run.

    PRIVATE BY DESIGN
    No account. No servers. No analytics, no tracking, nothing collected. Your workouts go to Apple Health, your routes stay on your watch, and your shoes and history stay on your phone. Nothing leaves your devices.

    Requires an Apple Watch with GPS. The iPhone app is the companion — your phone can stay in your pocket.

## What's New (4000)

For the first release:

    First release.

    Start a session on your watch and just move — Gaitway works out whether you're walking or running, pauses when you stop, and learns your routes as you go. Forks tell you what's down each way, segments give you your own pace to beat, and the phone app maps the network you've built up.

---

# Testing (TestFlight)

## Beta App Description

    Gaitway is a watch-first walk/run app. It detects walking from running by step cadence, auto-pauses after five seconds standing still, and saves a mixed outing to Health as separate walk and run workouts. As you build up runs, it learns your junctions and the stretches between them: your wrist shows what's down each way at a fork, and your own pace to beat on the stretch you're running.

## What to Test (4000)

    Thanks for testing. The app is watch-first — start a session on the watch and let the phone sit in your pocket.

    WORTH A LOOK
    • Walk/run switching. Walk for a few minutes, then run, then walk again. Does the mode on the watch match what you're actually doing, and does it switch within a few seconds without flapping back and forth? If it feels wrong for your gait, change "Run pace" on the start screen.
    • Auto-pause. Stop at a crossing. It should pause after about five seconds and resume on its own when you set off.
    • Finishing. Press End once — it shows "Saving…" for a few seconds, then asks for effort. A mixed outing asks for walking and running effort separately.
    • Kilometre splits. Each km pops up with its time and a plus/minus against your own history over the same ground. Second run onwards is when the plus/minus starts meaning anything.
    • Forks. From your second or third run over the same ground, a fork pop-up should appear about 50 m before junctions, showing each way's distance, the pace to beat, and the quickest way home. Swipe right mid-run for the same thing as a page.
    • Phone: Network tab. Everywhere you've run, drawn as segments joined at junctions. Tap a segment for how often you've run it each way and your best time.
    • Phone: Route tab. Pick segments to build a route, send it to the watch, then run it — the watch shows only the turn the route calls for, plus distance to go.

    WHAT I'D LIKE TO KNOW
    • Anything that reads wrong at running pace — text too small, a number you couldn't parse in a glance.
    • Junctions marked where there isn't one, or a real junction that never shows up. A screenshot of the Network tab with the spot circled is the most useful thing you can send.
    • Battery: roughly what the watch drops over an hour's session.

    KNOWN AND EXPECTED
    • A brand new install has nothing to show on the Network and Route tabs until a run or two has synced from the watch.
    • Forks need a couple of passes over the same ground before they appear — one run won't do it.
    • The watch may ask for location permission again after installing a new build; grants don't carry across installs.

## Test information — feedback email / marketing / privacy URLs

    Marketing URL:      https://gaitway.robbo-online.uk
    Privacy policy URL: https://gaitway.robbo-online.uk/privacy.html
    Support URL:        https://gaitway.robbo-online.uk

---

# App Review notes

Paste into "Notes" in the App Review Information section. This app is
easy to under-demonstrate: a reviewer indoors sees mostly empty
screens, so say so up front.

    No account or login is required. There is nothing to sign in to — the app has no servers and no back end.

    HOW TO EXERCISE THE APP
    Gaitway is watch-first. The iPhone app is a companion: it shows shoes, run history, and maps built from workouts that sync over from the watch.

    1. On the Apple Watch, open Gaitway and press Start. Grant Health, Motion & Fitness, and Location ("While Using App") when asked.
    2. The session records immediately. Indoors it will show time and heart rate; distance and the route need GPS, so it stays near zero until the watch is outside.
    3. Press End once. The watch shows "Saving…" for a few seconds while the workout is written to Health, then asks for a 1–10 effort score. Saving completes the session and syncs it to the iPhone app.
    4. On the iPhone, the History tab now lists the workout. The Shoes tab works without any workout at all — add a pair with "+".

    WHAT WILL LOOK EMPTY, BY DESIGN
    The Network and Route tabs draw from GPS routes recorded on the watch. On a fresh install with no outdoor runs they show an empty state explaining this. Junction detection needs several passes over the same ground, so these features cannot be fully demonstrated without repeated outdoor workouts in one area.

    LOCATION AND BACKGROUND MODES
    The watch app requests When In Use location and declares the location background mode, so a workout keeps recording its route while the app is not frontmost — the standard pattern for a workout app. Location is used only to measure distance, draw the route, and recognise junctions on previous routes. It is never sent anywhere.

    HEALTHKIT
    Workouts, heart rate, distance, active energy and (watchOS 11+) the workout effort score are read from and written to Apple Health on the user's own device. No health data leaves the device.

    PRIVACY
    The app collects nothing, contains no analytics or third-party SDKs, and makes no network requests. The only data transfer is directly between the user's own paired iPhone and Apple Watch over WatchConnectivity.

---

# App Privacy (nutrition label)

Answer "No" to data collection throughout. For reference when filling
in the questionnaire:

- Data collected: **none**. The app has no servers and makes no
  network requests, so nothing is collected, linked, or used for
  tracking.
- Health & Fitness, Location, and Identifiers are all used on-device
  only and are not collected.

# Other fields

- **Category**: Health & Fitness (primary), Sports (secondary)
- **Age rating**: 4+
- **Copyright**: 2026 Paul Robinson
- **Screenshots**: `appstore/01-…` through `06-…` (1242 × 2688, 6.5")
