# Be Here Now

A SwiftUI macOS menu bar app that hides applications after they lose focus.
Requires macOS 14 or later. No third-party dependencies.

The default delay is 60 seconds. Open **Hide delays…** from the eye icon
to change it or enable a custom delay for a running application. Delays accept
seconds or minutes, from one second to 24 hours. Settings survive restarts and
application relaunches. Turn off an application's custom delay to use the default.
Opening **Hide delays…** activates Be Here Now and brings settings forward.
Be Here Now excludes itself from automatic hiding.

Hiding affects all windows of an application, like Command-H. It does not close
windows or quit applications. Returning to an application resets its timer.
Existing inactive applications start their timers when Be Here Now launches.
Timers restart after wake or returning to the user session.

## Build and run

With Xcode installed, run these commands from the project directory (fish compatible).

```fish
sh scripts/build-app
open 'build/Be Here Now.app'
```

The script builds for the current Mac's architecture. It reuses Mu's signing
configuration: `MU_SIGN_IDENTITY`, then `~/.config/mu/signing-identity`, then
ad-hoc signing if neither is configured. An empty or invalid configured identity
fails the build rather than falling back. Developer ID signing enables hardened
runtime and includes Apple's secure timestamp. No additional entitlements are needed.

To explicitly request an ad-hoc development build (fish compatible):

```fish
env MU_SIGN_IDENTITY=- sh scripts/build-app
```

For development, open `Package.swift` in Xcode. Run tests with `swift test`.

To create a signed, notarized release with a stapled ticket:

```fish
sh scripts/release
```

This reuses `MU_NOTARY_PROFILE` or `~/.config/mu/notary-profile` and its existing
Keychain credentials. It requires Developer ID signing, checks Apple's submission
status is `Accepted`, validates the stapled ticket, and checks Gatekeeper before
creating `build/BeHereNow.zip`. Rebuilding the app requires notarizing it again.

## Manual verification

Set a custom delay of five seconds for a disposable application such as TextEdit.
Switch to another application and confirm TextEdit hides after five seconds.
Return before five seconds and confirm it stays visible and gets a fresh delay
on the next switch. Check that the focused application never hides. Quit and
reopen Be Here Now to check persistence. Sleep and wake the Mac to check that
inactive applications get their full delay again.
