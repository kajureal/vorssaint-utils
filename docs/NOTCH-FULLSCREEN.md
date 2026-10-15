# Fullscreen island visibility

The island automatically hides while its display shows fullscreen content and
returns to its normal resting presentation after fullscreen ends. This includes
native fullscreen apps and browser videos, such as Netflix in Chrome. Hover,
shortcuts, notifications and media-key feedback cannot reveal the island while
it is hidden. Other displays can continue showing their islands.

The existing **Hide content in full screen** setting controls this behavior. It
defaults on; an explicitly saved off setting is preserved. The setting remains
part of settings backup. The physical camera notch is hardware and stays visible.

Native fullscreen uses the existing macOS Space topology bridge. A fallback reads
the foreground app's visible window bounds to detect players that fill a display
without entering a native fullscreen Space. It reads no window titles or pixels
and adds no Accessibility or Screen Recording permission requirement. A desktop
window covering the entire display is treated as fullscreen, including a window
maximized with both menu bar and Dock hidden. Ordinary maximized windows that
leave menu-bar or Dock space do not qualify.

App activation and Space changes update visibility immediately; a half-second
timer catches desktop video transitions and delayed Space updates. The timer
continues while the island is hidden so leaving fullscreen restores it, and
stops when the feature is disabled or the session cannot present the island.

The Space bridge uses private symbols already used by the app. If a macOS update
removes them, the foreground window-bounds fallback still works. If neither query
can establish fullscreen, the island stays available rather than remaining stuck
hidden. Fullscreen on another display is scoped through macOS's separate-Spaces
setting; a native shared fullscreen Space applies to every display.

## Verification

Verified on Apple Silicon, macOS 27.0.1, using the macOS 26 SDK:

- `./build.sh`: passed; produced the ad-hoc-signed app bundle.
- `notch` suite: all 71,812 checks passed, including native Space transitions,
  desktop window classification, polling restoration, timer lifecycle, hover
  suppression, and physical/simulated overlay presentation.
- Full suite: 15 failures among 117,310 checks. The same 15 failures reproduce
  in an untouched checkout of upstream commit `4244163b` (117,300 checks).
  The affected `updates`, `switcher-model`, and `features` groups pass in
  isolation on both checkouts (3,878 checks each).
- Preference cleanup, uninstall-Spaces and developer-install isolation passed.

The app selftest was not run because execution approval was declined. The user installed the compiled test build and reported that the feature worked.
Automated tests exercise production methods with controlled window and Space
inputs; multi-display hardware scenarios have not been verified interactively.
