---
name: verify
description: How to build, launch, and observe FileExplorer for end-to-end verification of browser/navigation changes.
---

# Verifying FileExplorer changes

## Build + install + launch

* `hammer build` - builds, installs to /Applications/FileExplorerByDux.app, and opens it.
* `swift test` runs the unit suite (101 tests), but tests alone are not verification.

## Driving the app without UI automation

Screen recording and accessibility permissions are usually NOT granted to the agent shell, so `screencapture` and `osascript`/System Events fail.
Drive and observe through these channels instead:

* Launch the binary directly with a path argument (navigates there at startup):
  `/Applications/FileExplorerByDux.app/Contents/MacOS/FileExplorer <dir> > app.log 2>&1 &`
  `open -a FileExplorerByDux <dir>` does NOT deliver open events reliably - use the CLI arg.
* `~/.config/dux-file-explorer/last-folder.txt` is written by every `navigateTo` - it is the observable side effect for navigation flows. Back it up before testing, and note the user may click the visible app window mid-test and overwrite it.
* External FS changes to the current folder trigger the kqueue watch: `touch` a file to force a debounced reload; `rm -rf` the current folder to force ancestor-recovery navigation (observable in last-folder.txt within ~1.5s).
* Folders with more than 1000 entries take the async listing path; 1000 or fewer take the sync no-flicker path.
* Process aliveness (`pgrep -f FileExplorerByDux`) after each poke catches crashes.

## Gotchas

* `standardizedFileURL` shortens `/private/tmp/...` to `/tmp/...` in saved paths - expected, pre-existing.
* The app window appears on the user's screen with every relaunch; keep the number of relaunches low.
* Purely visual behavior (breadcrumb rendering, flicker, dialogs, search UI) cannot be observed from the shell - list those for a manual pass.
