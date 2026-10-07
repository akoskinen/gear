# eFoil Racing Live — Mac screensaver

Shows the live view of riders broadcasting their rides full screen as a macOS
screensaver, in the page's TV mode (<https://api.efoilracing.nl/live?tv=1>),
which spotlights each live rider in turn. When nobody is live it can play
random clips of the eFoil Racing Experience podcast with sponsor overlays.

## Install

1. Get `eFoil Racing Live.saver`:
   - **Download:** open the latest *Mac screensaver* run under the repo's
     Actions tab and download the `eFoil-Racing-Live-screensaver` artifact, then unzip it.
   - **Or build it** (needs the Xcode command line tools, `xcode-select --install`):
     `apps/screensaver-mac/build.sh --install`
2. The download is not notarised by Apple, so clear the quarantine flag first:
   ```
   xattr -dr com.apple.quarantine ~/Downloads/eFoil\ Racing\ Live.saver
   ```
3. Double-click the `.saver` and choose to install it for this user.
4. System Settings → Screen Saver → pick **eFoil Racing Live**.

## Options

Under **Options…** in the Screen Saver settings you can change the page URL
and how often the page reloads (default every 30 minutes; 0 turns it off),
set the podcast folder, and turn the podcast sound on.
If the page can't load, the screensaver shows "retrying" and tries again
every 30 seconds.

**Show diagnostics on screen** adds a panel in the bottom-left corner showing
what the screensaver and the page see: window visibility, WebGL, animation
frame rate, the map canvas size, JavaScript errors and load events. The same
information goes to the system log; to follow it live, run this in Terminal
while the screensaver is running:

```
log stream --predicate 'eventMessage CONTAINS "EfoilLive"'
```

## Podcast clips when nobody is live

The screensaver checks the live rider list every 15 seconds. After two empty
answers in a row it fades to random 30-second segments of the podcast episodes;
when a rider goes live it fades straight back to the map.

**1. Prepare the folder on your Mac** (needs ffmpeg: `brew install ffmpeg`):

```
podcast-source/
  episodes/   your original episode files (.mp4 .mov .m4v .mkv), any size
  ads/
    ad_1/     overlay.png (transparent, 1920×1080) + a 5–10 s sound (.m4a .mp3 .wav)
    ad_2/
```

```
apps/screensaver-mac/podcast/prepare-podcast.sh podcast-source podcast-web
```

This makes 720p web copies of the episodes (about 9 MB per 30 s clip; the
originals are far too heavy to stream), copies the sponsors, and writes
`podcast-web/manifest.json`. Run it again after adding episodes or sponsors:
finished episodes are skipped.

**2. Upload** the contents of `podcast-web` with your SFTP app to a folder your
web host serves over **https://** (the screensaver can't use SFTP itself, and
macOS only allows secure addresses).

**3. In Options**, put that folder's https:// address in **Podcast folder**.

How clips and sponsors play:

- Each clip starts at a random point, skipping the first and last minute of
  the episode, and never repeats the same episode twice in a row.
- One sponsor appears per clip, centred in it, for the length of its sound
  (8 s if it has none). Sponsors take turns in folder-number order: ad_1,
  ad_2, … ad_10, then ad_1 again.
- Sound is off unless **Play podcast sound** is ticked in Options. With sound
  on, the conversation drops to a quarter of its volume while a sponsor plays.
- The clip length, skipped minutes and how often a sponsor appears are in
  `manifest.json` (`clipSeconds`, `skipStartSeconds`, `skipEndSeconds`,
  `adEveryClips`). Change them there; the screensaver picks them up each time
  it switches to the podcast.
- If the folder can't be reached, the screensaver stays on the map and tries
  the podcast again 10 minutes later.

## How it works

`Sources/EfoilLiveView.swift` is a `ScreenSaverView` hosting a `WKWebView`.
Any mouse or keyboard input dismisses it. Since macOS Sonoma the system often
keeps screensavers running after you wake the Mac, so the view also listens
for `com.apple.screensaver.willstop` and unloads the page itself.

The `.saver` is built with `swiftc` (no Xcode project), as a universal binary
for Apple Silicon and Intel, ad-hoc signed. CI builds it on every change under
this folder and runs `smoke-test.swift`, which loads the bundle the way macOS
does.
