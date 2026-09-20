# Privacy

Pingscape has no account, no analytics, no advertising and no server of its own.

**Right now the app sends no data anywhere.** It reads the network state of your device (interfaces, routes, DNS servers, proxy, Wi-Fi and cellular status) and shows it on screen. Nothing is stored except a few settings on your device.

## Permissions

- **Location (while in use):** iOS only lets an app read the name of the connected Wi-Fi network if it has this permission. Pingscape does not read or use your location.
- **Local network:** needed to look for devices on your network. Results stay on your device.

## Lookups that leave the device

Features that need the internet are off by default, start only when you ask for them, and are listed here before they ship. None exist yet. Planned:

- Your public IP address and the provider behind it (via a public service and the RIPEstat Data API).

The app's [privacy manifest](App/Resources/PrivacyInfo.xcprivacy) declares that no data is collected and nothing is used for tracking.
