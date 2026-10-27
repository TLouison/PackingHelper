# Packing Helper

Packing Helper is a currently unreleased iOS app built in SwiftUI and SwiftData that is designed to make your pre-trip anxiety lower by helping you keep track of everything you need to do to prepare for your trip.

## Setup

Requires Xcode with the iOS 26 SDK (the deployment target is iOS 26). Open `PackingHelper.xcodeproj` and use the `PackingHelper` scheme.

### Config.xcconfig

The app reads two values from a gitignored `Config.xcconfig` at the repo root, which the Xcode project uses as the app target's base configuration. `Info.plist` passes them to the app, so the key and URL are empty without it.

```
cp Config.xcconfig.example Config.xcconfig
```

Then fill in:

- `REVENUECAT_API_KEY`: your RevenueCat public SDK key (starts with `appl_`).
- `WORKER_URL`: the deployed Cloudflare Worker that proxies the AI assistant and Unsplash photos. Keep the `https:/$()/` form from the example so xcconfig doesn't treat `//` as a comment.

Both ship inside the app, so only put publishable values here. Real secrets (the Anthropic API key, the RevenueCat secret key) belong on the Worker.

### WeatherKit

`PackingHelper/PackingHelper.entitlements` includes the WeatherKit entitlement. To build with it, sign with your own team and make sure WeatherKit is enabled for the app's bundle ID in your Apple Developer account (Certificates, Identifiers & Profiles). Forecasts only load for trips starting within 5 days.

### Testing Plus purchases locally

`PackingHelperPlus.storekit` defines the monthly, yearly, and lifetime Plus products. To use it, choose Product > Scheme > Edit Scheme > Run > Options > StoreKit Configuration and select that file. The scheme doesn't set it by default. Plus is tracked through RevenueCat (entitlement `PackingHelperPlus`), so the AI assistant and Unsplash search additionally need a working `WORKER_URL`.

### Running on a physical iPhone

`scripts/run-on-device.sh` builds, installs, and launches the app on a connected iPhone, like pressing Run in Xcode. It needs `jq` and the Xcode command line tools, and uses `xcbeautify` for output if it's installed.

```
scripts/run-on-device.sh                  # first connected or paired iPhone
scripts/run-on-device.sh "Todd's iPhone"  # by name, UDID, or devicectl identifier
CONFIGURATION=Release scripts/run-on-device.sh
CONSOLE=1 scripts/run-on-device.sh        # stream app output after launch
```

It works over Wi-Fi if the phone is paired with "Connect via network" in Xcode's Devices window, and unlocks the login keychain for codesigning when run over SSH.

## More

See `CLAUDE.md` for architecture notes, `ROADMAP.md` for planned work, and `SPEC.md` for the template review design.
