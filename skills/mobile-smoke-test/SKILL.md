---
description: Build a mobile app (Android and/or iOS), install it on a local emulator/simulator, drive it through a UI flow via scripted taps, and capture screenshots as evidence that a change works end-to-end. Platform- and project-agnostic. Use when asked to smoke-test, manually verify, or visually confirm a mobile app change on a real running app rather than just via unit tests or CI.
allowed-tools:
  - Bash
  - Read
argument-hint: "<what to verify> [--android-only|--ios-only]"
---

# mobile-smoke-test

Drive a real Android emulator and/or iOS simulator to verify a mobile change works, with
screenshots as evidence. This skill only covers *driving the app* — project-specific setup
(test account credentials, which backend environment to point at, org-specific build flavors)
does **not** belong here. Check the project's own `CLAUDE.md`/`README` and the user's personal
rules file for that; if neither has it, ask.

Before installing any new tool this skill needs (e.g. `idb-companion`, which requires trusting a
new Homebrew tap), check whether a tool-install vetting skill is configured in this environment
and run it first — installing dev tooling from a new/untrusted source is exactly the kind of
action that should be surfaced to the user before it happens, not just before running the app.

---

## Android flow

1. **Locate the SDK.** Check `$ANDROID_HOME` / `$ANDROID_SDK_ROOT` first. Common fallback
   locations: `~/Library/Android/sdk`, or a Homebrew install at
   `/opt/homebrew/share/android-commandlinetools`. Put `platform-tools`,
   `cmdline-tools/latest/bin`, and `emulator` on `PATH` for this session.

2. **Find or create an AVD.**
   ```bash
   avdmanager list avd
   ```
   If none exist, list installed system images (`sdkmanager --list_installed | grep system-images`)
   and create one with `avdmanager create avd -n <name> -k "<system-image-package>" -d <device>`.

3. **Boot it in the background**, redirecting output to a log file (not to something you'll
   display — emulator boot logs are normally harmless, but treat any new subprocess's stdout with
   the same caution as the `idb_companion` warning below until you know otherwise):
   ```bash
   emulator -avd <name> -no-snapshot-load -no-boot-anim > /path/to/scratch/emulator.log 2>&1 &
   disown
   ```
   Wait for boot:
   ```bash
   adb wait-for-device
   until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
   ```

4. **Build the debug variant.** This is project-specific — check the project's `CLAUDE.md`/
   `README`/`build.gradle` for the right Gradle task (e.g. `./gradlew assembleDevelopDebug`) and
   any required env vars (package-registry credentials are common; check if they're already
   exported before assuming you need to source them from somewhere). Run the build in the
   background and monitor/poll rather than blocking — a cold build with no cache can take
   15–40+ minutes.

5. **Install:**
   ```bash
   adb install -r <path-to-apk>
   ```

6. **Launch:**
   ```bash
   adb shell pm list packages | grep -i <app-name>          # find the package
   adb shell cmd package resolve-activity --brief <package>  # find the launcher activity
   adb shell monkey -p <package> -c android.intent.category.LAUNCHER 1
   ```

7. **Drive the UI — prefer the accessibility tree over screenshot-guessing for native views:**
   ```bash
   adb shell uiautomator dump /sdcard/window_dump.xml
   adb pull /sdcard/window_dump.xml ./window_dump.xml
   grep -o 'text="<label>"[^/]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' window_dump.xml
   ```
   Parse `bounds="[x1,y1][x2,y2]"`, tap the center:
   ```bash
   adb shell input tap <center_x> <center_y>
   ```
   These are **raw device pixel coordinates**, matching `adb shell wm size` exactly — no scaling
   needed.

   **`uiautomator` cannot see inside WebViews or Chrome Custom Tabs** (e.g. an in-app OAuth login
   page rendered as a web view). For that content, fall back to screenshot-based tapping (step 8).

8. **Screenshot-based tapping fallback** (WebView/browser content only):
   ```bash
   adb exec-out screencap -p > step.png
   ```
   View the screenshot and estimate the tap point **directly in the screenshot's own pixel
   dimensions** — on Android, the screenshot is already full device resolution, and
   `adb shell input tap` takes the same raw pixel coordinates. No conversion needed. (This is
   different from iOS — see the note in the iOS section. Mixing the two up is an easy mistake.)

9. **Screenshot evidence:**
   ```bash
   adb exec-out screencap -p > evidence.png
   ```

---

## iOS flow

1. **List simulators:**
   ```bash
   xcrun simctl list devices available
   ```

2. **Boot one:**
   ```bash
   xcrun simctl boot <UDID>
   open -a Simulator
   ```

3. **Build for the simulator.** Find the right scheme from `xcodebuild -workspace <ws>.xcworkspace
   -list` (look for a "Debug"/"Dev"-flavored scheme pointed at a dev/staging backend, not
   production/release):
   ```bash
   xcodebuild -workspace <ws>.xcworkspace -scheme <DevScheme> -configuration Debug \
     -destination 'platform=iOS Simulator,name=<device>' -derivedDataPath <path> build
   ```
   **CocoaPods gotcha:** if the project uses CocoaPods, check for `Pods/` (it's normally
   gitignored — generated locally, not committed). A stale local `Pods/` directory that
   references source files deleted since it was last generated causes a cryptic
   `Build input file cannot be found` error. Fix: `bundle exec pod install` (or plain
   `pod install`) before building. This isn't a real compile error in your change — don't
   chase it as one.

4. **Install:**
   ```bash
   xcrun simctl install <UDID> <path-to-.app>
   plutil -p <path-to-.app>/Info.plist | grep CFBundleIdentifier   # get the bundle id
   ```

5. **Launch:**
   ```bash
   xcrun simctl launch <UDID> <bundle-id>
   ```

6. **Screenshot:**
   ```bash
   xcrun simctl io <UDID> screenshot evidence.png
   ```

7. **Drive the UI via `idb`** (Meta's simulator automation CLI — `simctl` alone has no touch
   injection):

   **One-time setup** (needs user confirmation before installing — this trusts a new Homebrew
   tap; run through the tool-install vetting process first if one is configured):
   ```bash
   brew tap facebook/fb
   brew trust facebook/fb          # Homebrew refuses to load formulae from an untrusted tap
   brew install idb-companion
   ```
   The `idb` Python client (`fb-idb`, last released years ago) **crashes on Python ≥3.12**
   (`RuntimeError: There is no current event loop in thread 'MainThread'` — the implicit
   event-loop-creation fallback its old code relies on was removed). Install it pinned to
   Python 3.11:
   ```bash
   asdf install python 3.11.15   # or any 3.11.x; check `asdf list all python` for available versions
   pipx install --python "$(asdf where python 3.11.15)/bin/python3.11" fb-idb
   ```
   Don't let `pipx` default to whatever the latest system Python is for this particular package.

   **Run the companion:**
   ```bash
   idb_companion --udid <UDID> > /dev/null 2>&1 &
   disown
   idb connect <UDID>
   ```
   > **Security note — do not skip this:** `idb_companion` dumps its **full inherited shell
   > environment** (`Invoked with args=... env={...}`) to stdout on startup. If any real secrets
   > are exported in your shell (API tokens, etc.), they will appear in that output verbatim.
   > **Always** redirect straight to `/dev/null` — never to a log file you'll read, `cat`, or
   > otherwise display. If you ever do capture it by mistake, delete the file immediately and
   > tell the user their environment may have been exposed (including in the conversation
   > transcript, which you cannot retroactively scrub) — recommend rotating any real credentials
   > that appeared.

   **Inspect and tap:**
   ```bash
   idb ui describe-all --udid <UDID>
   ```
   Returns the accessibility tree as JSON with element frames in **points**, not pixels
   (density-independent — e.g. an iPhone 17 is 402×874pt regardless of the 1206×2622px
   screenshot). Find the element by `AXLabel`, tap its frame center:
   ```bash
   idb ui tap <x> <y> --udid <UDID>      # points
   idb ui text "some text" --udid <UDID>  # types into the focused field
   ```

   **`idb ui describe-all` does not see:**
   - Web content inside in-app browser/auth sessions (`ASWebAuthenticationSession`,
     `SFSafariViewController`) — e.g. an OAuth login page.
   - Sometimes the app's own `UITabBar`.

   For those, fall back to screenshot-based tapping — but note the **conversion iOS needs that
   Android doesn't**: `xcrun simctl io screenshot` produces a full-resolution **pixel** image,
   but `idb ui tap` takes **points**. Convert:
   ```
   point = pixel / density
   ```
   Get `density` from `idb describe --udid <UDID>` (in `screen_dimensions`, e.g. `3.0`). If
   you're estimating the tap point from a *displayed/scaled-down* rendering of the screenshot
   (rather than measuring the raw file), convert displayed→original pixel first, then
   pixel→point — two conversions, not one. Mixing this up (tapping with pixel coordinates, or
   with displayed-image coordinates unconverted) is the most common mistake here — if taps seem
   to land in the wrong place, check this first.

---

## General notes

- **Cold builds are slow.** No local cache in a fresh worktree/checkout is normal — expect
  15–40+ minutes for a first build on either platform. Kick the build off in the background
  and poll/monitor for completion; don't block on it synchronously.
- **Prefer the accessibility tree over eyeballing screenshots** whenever a native element is
  available (`uiautomator dump` on Android, `idb ui describe-all` on iOS) — it's exact and
  saves retries. Only fall back to screenshot-coordinate-estimation for WebView/browser content
  or chrome the accessibility API doesn't expose.
- **This skill doesn't know your project's specifics.** Test accounts, which backend/environment
  a build variant points to, and org-specific scheme/flavor names are out of scope — those live
  in the project's own docs or the user's personal rules file. If you need one and can't find it
  documented, ask rather than guessing or provisioning something new.
