# OmniChat

A native macOS SwiftUI application that unifies ChatGPT, Claude, and Gemini APIs into one beautiful interface with local chat history storage and proper LaTeX formula rendering.

## Features

- **Multiple AI Providers**: Seamlessly switch between OpenAI (ChatGPT), Anthropic (Claude), and Google (Gemini)
- **Local Chat History**: All conversations stored securely locally using SwiftData
- **Streaming Responses**: Real-time message streaming for a responsive user experience
- **Markdown Rendering**: Full markdown support with syntax-highlighted code blocks
- **LaTeX Support**: Render mathematical formulas with KaTeX (both inline and display modes)
- **Secure API Keys**: Store API keys securely in macOS Keychain
- **Keyboard Shortcuts**: Navigate and chat efficiently with intuitive shortcuts
- **Model Selection**: Choose from all available models for each provider with a dropdown selector

## Requirements

- macOS 14.0 or later
- Xcode 15.4+
- API keys for the providers you want to use:
  - OpenAI: https://platform.openai.com/api-keys
  - Anthropic: https://console.anthropic.com/
  - Google: https://aistudio.google.com/

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/OmniChat.git
cd OmniChat
```

2. Open the project in Xcode:
```bash
open OmniChat.xcodeproj
```

3. Build and run:
```bash
⌘B  # Build
⌘R  # Run
```

4. Add your API keys in Settings (⌘,)

## Usage

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New Chat |
| ⌘⌃S | Toggle Sidebar |
| ⌘L | Focus Message Input |
| ⌘↩ | Send Message |
| ⌘⇧⌫ | Clear Conversation |
| ⌘, | Settings |

### Model Selection

Click the model dropdown at the top of the chat window to select from available models:

**OpenAI:**
- gpt-4.1
- gpt-4.1-mini
- gpt-4o
- o4-mini
- o3-mini

**Anthropic (Claude):**
- claude-opus-4-5-20251101
- claude-sonnet-4-5-20250929
- claude-haiku-4-5-20250929

**Google (Gemini):**
- gemini-2.5-pro
- gemini-2.5-flash
- gemini-2.5-flash-lite

## Architecture

### Project Structure

```
OmniChat/
├── App/
│   └── OmniChatApp.swift           # App entry point with menu commands
├── Models/
│   ├── Conversation.swift          # Chat conversation model
│   ├── Message.swift               # Individual message model
│   └── APIProvider.swift           # Provider configuration
├── Services/
│   ├── KeychainService.swift       # Secure API key storage
│   └── APIService/
│       ├── APIServiceProtocol.swift    # Service interface
│       ├── OpenAIService.swift         # ChatGPT integration
│       ├── AnthropicService.swift      # Claude integration
│       └── GoogleAIService.swift       # Gemini integration
└── Views/
    ├── MainView.swift              # Root view with NavigationSplitView
    ├── Sidebar/
    │   ├── SidebarView.swift       # Conversation list
    │   └── ConversationRow.swift   # Conversation item
    ├── Chat/
    │   ├── ChatView.swift          # Main chat area
    │   ├── MessageView.swift       # Message bubble
    │   ├── MessageInputView.swift  # Text input
    │   └── ModelSelectorView.swift # Model dropdown
    ├── Settings/
    │   ├── SettingsView.swift      # Settings window
    │   └── APIKeyRow.swift         # API key input
    └── Components/
        ├── MarkdownView.swift      # Markdown renderer
        ├── CodeBlockView.swift     # Code block with copy button
        └── LaTeXView.swift         # LaTeX formula renderer
```

### Data Model

**Conversation** (SwiftData Model)
- `id`: UUID
- `title`: String
- `createdAt`: Date
- `updatedAt`: Date
- `messages`: [Message]

**Message** (SwiftData Model)
- `id`: UUID
- `role`: MessageRole (user/assistant)
- `content`: String
- `timestamp`: Date
- `modelUsed`: String? (e.g., "gpt-4.1")

## Implementation Details

### API Streaming

All services implement streaming responses using `AsyncThrowingStream<String, Error>` for real-time message delivery.

- **OpenAI**: Server-Sent Events (SSE) with `data:` prefixed JSON
- **Anthropic**: SSE with `content_block_delta` events
- **Google**: Newline-delimited JSON streaming

### Security

- API keys are stored in macOS Keychain using `SecItem` APIs
- No credentials are logged or persisted to disk
- Settings are stored securely in the system's standard locations

### Markdown & LaTeX

- **Markdown**: Uses SwiftUI's native `AttributedString(markdown:)` for inline parsing
- **LaTeX**: Rendered via KaTeX loaded from CDN, displayed in WKWebView components
- **Mixed Content**: MarkdownView intelligently handles both markdown and LaTeX in the same message

## Development

### Building

```bash
xcodebuild -scheme OmniChat -configuration Debug build
```

### Running Tests

Tests can be added in the `OmniChatTests` directory (currently empty).

## Known Limitations

- LaTeX rendering requires internet connection (uses KaTeX CDN)
- Conversations are not synced across devices
- No message search functionality (Phase 8+ feature)
- No custom prompt templates (future enhancement)

## Future Enhancements

- [ ] Message search and filtering
- [ ] Conversation sharing/export
- [ ] Custom system prompts
- [ ] Voice input/output
- [ ] Image generation support
- [ ] Conversation folders/organization
- [ ] Dark mode refinements
- [ ] Export to PDF/Markdown
- [ ] Multi-window support
- [ ] Offline LaTeX rendering

## Contributing

This is a personal project, but suggestions and improvements are welcome!

## License

MIT License - feel free to use and modify as needed.

## Support

For issues with the app:
1. Check your API key configuration in Settings
2. Ensure you have the required API credits
3. Try with a different model
4. Check internet connectivity for LaTeX rendering

For API-specific issues, consult the provider's documentation:
- [OpenAI API Docs](https://platform.openai.com/docs)
- [Anthropic API Docs](https://docs.anthropic.com/)
- [Google AI API Docs](https://ai.google.dev/)

## Changelog

### v0.1.0 (Initial Release - 2026-01-27)

**Implemented:**
- Phase 1: Project setup with SwiftUI and SwiftData
- Phase 2: UI shell with NavigationSplitView and welcome screen
- Phase 3: Local storage using SwiftData
- Phase 4: OpenAI API integration with streaming
- Phase 5: Markdown rendering with code blocks
- Phase 6: LaTeX formula rendering with KaTeX
- Phase 7: Anthropic (Claude) API and Google (Gemini) API integration
- Phase 8: Keyboard shortcuts and menu commands

**Models Available:**
- OpenAI: 5 latest models
- Anthropic: 3 latest Claude models
- Google: 3 latest Gemini models

**Features:**
- Real-time streaming responses
- Secure API key management via Keychain
- Local conversation history
- Beautiful SwiftUI interface with custom avatars
- Model switching mid-conversation
- Code block copy functionality
- Mathematical formula rendering
