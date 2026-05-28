# Helm

A private iOS/iPadOS reader for the Markdown and HTML files that live on your own
machines — reached over [Tailscale](https://tailscale.com) via SSH/SFTP.

Helm is a **reader, not a terminal**. You add a host (like an `~/.ssh/config` entry),
it connects over your tailnet, you browse to a `.md`/`.html` file, and it renders
cleanly — headings, code blocks, tables, dark mode. No companion server runs on your
machines; Helm uses the SSH server that's already there.

## Why

Your notes and wikis already live on your laptop, NAS, or VPS. Tailscale already makes
those machines reachable from anywhere. Helm is the missing piece: a focused, elegant
way to *read* that Markdown on your phone — without copying files around, running a
sync service, or settling for a raw-text SSH client.

## Features

- **SSH/SFTP browsing** — folders and `.md`/`.markdown`/`.html` files only.
- **Styled reader** — Markdown rendered to themed HTML (light/dark) via
  [swift-markdown](https://github.com/apple/swift-markdown); HTML files render directly.
- **Three auth methods** — **Tailscale SSH** (keyless), private key (OpenSSH
  ed25519/RSA, optional passphrase), or password. Secrets live in the iOS Keychain.
- **Shortcuts** — star files *and folders*; they sit on the home screen for one-tap access.
- **Live host status**, **in-document links + table of contents**, **full-text search**
  (server-side `grep`), **offline cache**, and **read-aloud**.
- **Ask about this doc** (iOS 26+) — on-device [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
  answer questions about the current file, fully private, no network.
- **Minimal settings** — reader text size and clear-cache.

## Requirements

- iOS/iPadOS 17+ (the "Ask" feature requires iOS 26 + Apple Intelligence).
- Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- The [Tailscale](https://tailscale.com) app installed and connected on the device —
  it provides the network path to your machines. Helm does not establish the tunnel itself.

## Build

```bash
brew install xcodegen          # one-time
make generate                  # generates Helm.xcodeproj from project.yml
make build                     # build for the simulator
make test                      # run the test suite
```

To run on a device, set your Apple Developer Team ID in `Signing.xcconfig` (copied
from `Signing.xcconfig.example` on first `make generate`; it's gitignored), then:

```bash
make install-device DEVICE_ID=<your-device-id>   # see: xcrun devicectl list devices
```

## Architecture

- **SwiftUI**, Swift 6, strict concurrency. No app-level state outside `AppState`.
- **`SFTPBrowser`** — connection-pooled SSH/SFTP via [Citadel](https://github.com/orlandos-nl/Citadel)
  (SwiftNIO SSH). `list` / `read` / `search` are the core operations.
- **`MarkdownHTMLRenderer` + `HTMLTheme`** — CommonMark/GFM → styled HTML in a `WKWebView`.
- **Keychain** for all credentials; **UserDefaults** for host metadata and favorites.

See [`PRODUCT_GOAL.md`](PRODUCT_GOAL.md) for the product shape and
[`TAILSCALE_SSH_SETUP.md`](TAILSCALE_SSH_SETUP.md) for enabling keyless access.

## Roadmap

- **v2** — chat across your whole wiki (the SFTP operations are already the tool layer
  for an agentic loop; on-device for single docs, cloud for big context).
- **v3** — editing files back over SFTP.
