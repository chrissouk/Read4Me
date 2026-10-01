# Read4Me for iPhone

Open `Read4Me.xcodeproj`, select the **Read4Me** scheme, and run on an iOS 17+ simulator or iPhone. For an iPhone, choose your Apple development team under Signing & Capabilities and change the bundle identifier if needed. No packages, server, API key, or Python installation are required by the iOS app.

## First audiobook

1. Tap **Import PDF** and choose a PDF containing selectable text.
2. Open **Preview extracted text** to inspect and correct extraction before conversion. Scanned PDFs without text are rejected; OCR is not included.
3. Choose an installed Apple voice and tap **Listen to voice sample**. Additional voices may need to be downloaded through iPhone Settings before offline use.
4. Tap **Create audiobook**. Keep the app foregrounded during conversion. Leaving the app requests a pause after the current section; iOS can suspend that section before completion. Reopen and resume. Completed sections survive process termination; the unfinished section is regenerated.
5. Play the saved audiobook. Adjust speed, skip back 15 seconds or forward 30 seconds, scrub, or set a sleep timer. Playback position and speed are persisted every five seconds and on pause, seeking, and scene transitions. An abrupt process termination can lose up to five seconds of progress.
6. Lock your iPhone and use the system Now Playing controls. Reopen the app to restore the most recently loaded book at its saved position, paused.

PDFs, extracted text, conversion metadata, and audio live in the app's Documents/Library directory, with separate UUID directories for every import. Reimporting the same filename creates another independent book. Delete a book with its library-row swipe action. Text and voice choices are frozen once conversion begins to keep resumed sections consistent.

Apple synthesis writes PCM CAF sections locally. This is an offline prototype and uses more storage than compressed MP3. Playback queues the saved sections; tiny transition gaps are possible. The existing Python/OpenAI MP3 workflow remains available separately. Compare the same short passage with Apple narration and the Python pipeline before choosing narration quality for release. The iOS app makes no OpenAI requests.

## CarPlay activation after approval

The app already provides background audio, Now Playing metadata, remote play/pause, seeking, and skip controls. `CarPlaySceneDelegate.swift` also provides a library of completed audiobooks and opens Apple's Now Playing template.

Dedicated CarPlay presentation is intentionally inactive in the default build until Apple approves the [CarPlay audio entitlement](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements). To activate it with an approved developer account:

1. Add the granted `com.apple.developer.carplay-audio` entitlement to the app's signing entitlements and use a matching provisioning profile. `CarPlay/Read4Me.entitlements` is the entitlement template; set `CODE_SIGN_ENTITLEMENTS` only after approval.
2. Merge `CarPlay/SceneConfiguration.plist` into `UIApplicationSceneManifest` in `Read4Me/Info.plist` (retain `UIApplicationSupportsMultipleScenes`).
3. Test the library, switching books, system controls, disconnection, and reconnection in CarPlay Simulator and an actual vehicle. Conversion and PDF import stay on the phone.

Live Activities are deferred. The implementation does not claim unrestricted background conversion; background audio mode supports listening, not guaranteed synthesis execution.

## Validation

```sh
xcodebuild -project ios/Read4Me.xcodeproj -scheme Read4Me \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/read4me-build CODE_SIGNING_ALLOWED=NO build

xcodebuild -project ios/Read4Me.xcodeproj -scheme Read4Me \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/read4me-build CODE_SIGNING_ALLOWED=NO test
```

Run the commands from the repository root; adjust the simulator name to an installed device. Tests cover bounded Unicode-aware chunking, blank PDFs, duplicate filenames, catalog persistence, saved-audio seeking and restoration, and actual Apple narration with completed-section reuse. The speech integration test requires an installed English voice.

Before release, test on a physical iPhone: import a real multi-page PDF, interrupt/relaunch conversion, compare narration quality, play with the screen locked across section boundaries, operate Bluetooth/headphone controls, disconnect headphones, receive a phone call, allow the sleep timer to expire while locked, and terminate/reopen the app to check resume. CarPlay requires its separate entitlement and device validation. Text extraction reads PDFs in their embedded text order; complex columns may need manual correction.
