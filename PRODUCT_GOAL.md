# Helm Product Goal

Helm is a private iOS/iPadOS reader and voice-capture tool for Markdown and HTML files that live on your own machines, reached over Tailscale via SSH/SFTP.

It runs on iPhone and iPad. It connects to hosts you add — there is nothing hardcoded. Tailscale provides the private network path to each machine; SFTP reads the remote filesystem. No companion service runs on the hosts: Helm uses the SSH server (`sshd`) that is already there.

## Shape

- **Hosts** mirror an `~/.ssh/config` entry: nickname, hostname (a Tailscale `100.x` IP or MagicDNS name), port, username, auth, and a starting directory.
- **Authentication** is an SSH private key (OpenSSH ed25519 or RSA, optional passphrase) or a password. Secrets live in the iOS Keychain (device-bound, not iCloud-synced), never in UserDefaults or the app bundle.
- **Browsing** is directory-scoped over SFTP, starting at the host's start directory. Only sub-directories and `.md`/`.markdown`/`.html` files are shown — Helm is a wiki client, not a file manager. Full-text results carry remote modification dates and can be searched newest- or oldest-first.
- **Reading and writing** renders Markdown through swift-markdown into styled HTML in a `WKWebView` (light/dark aware); `.html` files render directly. Markdown can be edited with conflict detection and saved back over SFTP. Read-aloud and favorites are available per file.
- **Voice notes** record from the device microphone, transcribe on device using Apple Speech, format the transcript as Markdown with YAML front matter, and save it under the configured wiki root's `transcripts` folder over SFTP by default.
- **Change requests** attach spoken feedback to the page being read. Helm writes a structured, reviewable request under `.helm/requests/pending`; Markdown targets can also be edited directly, while HTML requests tell the machine-side agent to locate the canonical source instead of blindly editing generated output.
- **Favorites / shortcuts** save individual files *and folders* across all hosts; shortcuts sit on the home screen for one-tap access (folders deep-link into the browser, files open the reader).
- **Settings** are intentionally minimal: reader text size, clear-cache, and voice-capture destination.
- **Ask about this doc** (iOS 26+): an on-device Apple Foundation Models chat answers questions about the current document, fully private, no network — the first step toward a v2 "chat with your wiki."

## Connection model

```
iPhone (Tailscale on) ──SSH/SFTP──▶ host (sshd, port 22)
```

Helm requires the Tailscale app installed and connected on the device to provide reachability to `100.x`/MagicDNS addresses; it does not establish the tunnel itself. Host keys are currently accepted on first use (TOFU pinning is a possible later addition).

## App Requirements

- Add / edit / delete hosts, with key import (paste or Files) and Keychain-backed secrets.
- SFTP directory browser with folder navigation and Markdown/HTML filtering.
- Native Markdown reader (rendered as styled HTML) and HTML reader.
- Favorites/shortcuts for files and folders, surfaced on the home screen.
- Live host reachability status; clear unreachable / auth-failed / not-found states.
- In-document links + table of contents, chronologically sortable server-side full-text search, offline cache.
- Conflict-aware Markdown editing and SFTP save.
- Text-to-speech read-aloud and on-device "Ask about this doc" (iOS 26+).
- Voice-note capture with microphone permission, Speech permission, transcript review, and SFTP save.
- Page-attached voice change requests written to `.helm/requests/pending` for processing in the separate machine-side coding workflow.

## Distribution

Personal / sideload. No hardcoded hosts or tailnet values; clean first-run empty state. App Store polish (privacy manifest, full accessibility pass) is deferred.

## Implementation

- iOS app in `Helm/` (SwiftUI, Swift 6, strict concurrency).
- SSH/SFTP via [Citadel](https://github.com/orlandos-nl/Citadel) (SwiftNIO SSH).
- Markdown via [swift-markdown](https://github.com/apple/swift-markdown).
- Voice transcription reuses TokDown's on-device Speech pipeline, adapted for microphone recordings instead of pendant audio.
