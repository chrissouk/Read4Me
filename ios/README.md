# Read4Me for iPhone

Open `Read4Me.xcodeproj`, select the **Read4Me** scheme, and run on an iOS 17+ simulator or iPhone. For an iPhone, choose your Apple development team under Signing & Capabilities and change the bundle identifier if needed. No packages, hosted file server, or Python installation are required by the iOS app. An OpenAI API key and internet access are required to create narration. Saved audio plays offline.

## First audiobook

1. Open **Settings** using the gear button. Tap **Get an OpenAI API key** to open [the OpenAI Platform key page](https://platform.openai.com/api-keys), create a key, paste it in the secure field, and tap **Save API key**. The key is stored in this device’s Keychain, not in the library or source code. API billing is separate from ChatGPT; Settings also links to API billing.
2. Tap **Import PDF** and choose a PDF containing selectable text.
3. Open **Preview extracted text** to inspect and correct extraction before conversion. Scanned PDFs without text are rejected; OCR is not included.
4. The default narrator is **onyx**, using **gpt-4o-mini-tts** and **be fluent & clear, like a podcast narrator**, matching `text_to_speech.py`. Choose another OpenAI voice or edit narration instructions if desired.
5. Tap **Create audiobook**. Keep the app foregrounded during conversion. Leaving the app requests a pause after the current section; iOS can suspend that section before completion. Reopen and resume. Completed sections survive process termination; the unfinished section is regenerated.
6. Play the saved audiobook. Adjust speed, skip back 15 seconds or forward 30 seconds, scrub, or set a sleep timer. Playback position and speed are persisted every five seconds and on pause, seeking, and scene transitions. An abrupt process termination can lose up to five seconds of progress.
7. Lock your iPhone and use the system Now Playing controls. Reopen the app to restore the most recently loaded book at its saved position, paused.

PDFs, extracted text, conversion metadata, and audio live in the app's Documents/Library directory, with separate UUID directories for every import. Reimporting the same filename creates another independent book. Delete a book with its library-row swipe action. Text and voice choices are frozen once conversion begins to keep resumed sections consistent.

The SwiftUI frontend follows the original PDF → text → sentence chunks → OpenAI speech → saved MP3 workflow. It calls the same `/v1/audio/speech` API directly from the iPhone with the user’s key; it does not run the Python interpreter or require a hosted backend. The Python scripts remain unchanged. Chunking keeps the Python 3,500-character target and sentence boundaries, with hard splitting for oversized sentences. Playback queues the MP3 sections instead of requiring ffmpeg to merge them on iOS. Model, voice, and narration instructions are persisted with the conversion so a retry cannot silently change the narrator.

Creating audio sends the extracted text to OpenAI and uses your API credits. There is no Apple speech-generation path. Existing Apple-generated CAF audio stays playable; tap **Recreate with OpenAI** on an old book to replace its narration. This keeps its PDF and text but resets its audio and playback position. Old incomplete conversions also use this action rather than mixing Apple and OpenAI sections. Re-creation uses API credits.

Missing or invalid keys, API rate limits, and exhausted quota have actionable errors. Failed sections remain retryable; already validated and saved MP3 sections are reused on resume. Requests are not automatically retried because another successful generation could be billed again. Removing the key prevents new generation and does not affect existing saved audio.

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
  -derivedDataPath /tmp/read4me-build CODE_SIGN_IDENTITY=- test
```

Run the commands from the repository root; adjust the simulator name to an installed device. Tests cover bounded sentence-aware chunking, blank PDFs, duplicate filenames, catalog persistence, saved-audio seeking and restoration, Keychain save/replace/removal, OpenAI request settings, invalid and missing keys, partial conversion retry, and legacy narration replacement. API responses are intercepted and use a silent MP3 fixture; tests do not need a real key or spend API credits. Simulator test signing stays enabled for Keychain access.

Before release, test on a physical iPhone: import a real multi-page PDF, use your API key to generate a short onyx sample, interrupt/relaunch conversion, play with the screen locked across section boundaries, operate Bluetooth/headphone controls, disconnect headphones, receive a phone call, allow the sleep timer to expire while locked, and terminate/reopen the app to check resume. CarPlay requires its separate entitlement and device validation. Text extraction reads PDFs in their embedded text order; complex columns may need manual correction.
