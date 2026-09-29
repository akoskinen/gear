# eFoil Racing Live — Mac screensaver

Shows the live view of riders broadcasting their rides
(<https://api.efoilracing.nl/live>) full screen as a macOS screensaver.

## Install

1. Get `eFoil Racing Live.saver`:
   - **Download:** open the latest *Mac screensaver* run under the repo's
     Actions tab and download the `eFoil-Racing-Live-screensaver` artifact, then unzip it.
   - **Or build it** (needs the Xcode command line tools, `xcode-select --install`):
     `apps/screensaver-mac/build.sh --install`
2. The download is not notarised by Apple, so clear the quarantine flag first:
   ```
   xattr -dr com.apple.quarantine ~/Downloads/"eFoil Racing Live.saver"
   ```
3. Double-click the `.saver` and choose to install it for this user.
4. System Settings → Screen Saver → pick **eFoil Racing Live**.

## Options

Under **Options…** in the Screen Saver settings you can change the page URL
and how often the page reloads (default every 30 minutes; 0 turns it off).
If the page can't load, the screensaver shows "retrying" and tries again
every 30 seconds.

## How it works

`Sources/EfoilLiveView.swift` is a `ScreenSaverView` hosting a `WKWebView`.
Any mouse or keyboard input dismisses it. Since macOS Sonoma the system often
keeps screensavers running after you wake the Mac, so the view also listens
for `com.apple.screensaver.willstop` and unloads the page itself.

The `.saver` is built with `swiftc` (no Xcode project), as a universal binary
for Apple Silicon and Intel, ad-hoc signed. CI builds it on every change under
this folder and runs `smoke-test.swift`, which loads the bundle the way macOS
does.
