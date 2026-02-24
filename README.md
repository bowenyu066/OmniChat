<div align="center" style="font-size: 24px;">
  <!-- <p>I know you are tired and sick of having to switch among ChatGPT, Gemini, and whatever apps,</p>
  <p>just to find the best AI that fits your personality.</p>
  <p>I also know that you feel like sometimes you are slowly "kidnapped" by one of them, </p>
  <p>because they carry all your emotions, your memories, your histories, and your late-night teas.</p>
  <p>One day you may find out you do not love them anymore.</p>
  <p>I know you want to leave, you want to take on a break, you want to find something new.</p>
  <p>But I completely understand that this is hard.</p>
  <p>It is just too hard to discard old memories and be forced to start off blank.</p>
  <p>That's why we bring you <b>OmniChat</b>.</p>
  <p>It is designed to carry all your memories and allow smooth transitions among all the models you love.</p>
  <p>No more rushing around, no more crying alone. All of you are stored safely here.</p>
  <p>Models are just guests, but <b><i>you are the real landlord</i></b>.</p> -->
  <img src="https://github.com/bowenyu066/OmniChat/blob/main/OmniChat/Resources/new_icon-256.png" alt="OmniChat">
</div>

# OmniChat

A native macOS app that unifies ChatGPT, Claude, and Gemini into one interface. Your conversations and memories stay local—switch models freely without losing context.

## Key Features

| Feature | Description |
|---------|-------------|
| **Multi-Provider** | GPT-5.2, Claude Opus 4.5, Gemini 3 Pro—all in one app |
| **Memory System** | Persistent knowledge that follows you across conversations |
| **Multimodal** | Drag-drop images and PDFs into any chat |
| **Local Storage** | All data stays on your Mac via SwiftData |
| **Streaming** | Real-time responses with Markdown and LaTeX rendering |
| **Workspaces** | Index local codebases for context-aware coding assistance |

## Quick Start

```bash
git clone https://github.com/bowenyu066/OmniChat.git
open OmniChat/OmniChat.xcodeproj
# Build & Run (⌘R), then add API keys in Settings (⌘,)
```

**Requirements:** macOS 14.0+, Xcode 15.4+

**Get API Keys:**
[OpenAI](https://platform.openai.com/api-keys) · [Anthropic](https://console.anthropic.com/) · [Google AI](https://aistudio.google.com/)

## Keyboard Shortcuts

| Shortcut | Action | Shortcut | Action |
|----------|--------|----------|--------|
| ⌘N | New Chat | ⌘L | Focus Input |
| ⌘↩ | Send Message | ⌘⇧A | Add Attachment |
| ⌘M | Memory Panel | ⌘, | Settings |
| ⌘⌃S | Toggle Sidebar | ⌘⇧⌫ | Clear Chat |

## Available Models

- **OpenAI:** GPT-5.2 (reasoning), GPT-5 Mini, GPT-4o
- **Anthropic:** Claude Opus 4.5, Sonnet 4.5, Haiku 4.5
- **Google:** Gemini 3 Pro, Gemini 3 Flash (Preview)

## Memory System

Create persistent memories (facts, preferences, instructions) that automatically inject into conversations. Control which memories each chat can access. Save important AI responses as new memories with one click.

## Security

- API keys stored in macOS Keychain
- Default behavior: no authentication prompt on app launch
- API Keys screen requires Touch ID/password authentication (settings-session scoped)
- Optional launch authentication with configurable grace period (1 / 7 / 30 days)
- App Sandbox enabled
- All data stored locally

### Keychain Authorization Stability (Debug + Release)

To avoid repeated local password prompts after rebuilds, keep code signing identity stable:

1. Use the same `DEVELOPMENT_TEAM` for Debug and Release.
2. For local Debug runs, default is **Sign to Run Locally**; switch to **Apple Development** if you want stable Keychain authorization across rebuilds.
3. Use Developer ID Application signing for release artifacts.

If signing changes and Keychain access is denied once, open **Settings -> API Keys** and run **Rebind Keychain Access** to re-save keys under the current signature.

## In-App Updates (Sparkle)

OmniChat supports industry-standard in-app updates via [Sparkle](https://sparkle-project.org/) (the same updater used by many non-App-Store macOS apps).

To enable secure in-app updates in production:

1. Sign builds with your **Developer ID Application** certificate (not "Sign to Run Locally").
2. Notarize and staple the app for each release.
3. Set these app metadata keys:
   - `SUFeedURL`: URL to your `appcast.xml`
   - `SUPublicEDKey`: your Sparkle EdDSA public key
4. Publish signed update archives and update the appcast.

Generate/update `appcast.xml` for a release with:

```bash
./scripts/update_appcast.sh v0.4.0-beta ~/Downloads/OmniChat-v0.4.0-beta.dmg omnichat
```

This script signs the DMG with Sparkle (`sign_update`) and writes a valid appcast entry.

If Sparkle is not fully configured, OmniChat automatically falls back to manual GitHub update notifications.

## License

MIT License

## Links

[Changelog](CHANGELOG.md) · [Issues](https://github.com/bowenyu066/OmniChat/issues)
