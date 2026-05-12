# Simpanin

SwiftUI prototype generated from the Simpanin Bookmark Manager Figma Home screen.

## Build IPA with GitHub Actions

1. Push this repository to GitHub on the `main` branch.
2. Open **Actions**.
3. Run **Build TrollStore IPA** manually, or let it run on `main` pushes.
4. Download the `Simpanin-TrollStore` artifact.
5. Open `Simpanin-TrollStore.ipa` with TrollStore on a supported device.

The workflow builds an unsigned Release app and packages it as:

```text
Payload/Simpanin.app
Simpanin-TrollStore.ipa
```

The app targets iOS 16.0 and uses bundle ID `com.local.simpanin`.
