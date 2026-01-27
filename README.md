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
git clone https://github.com/bowenyu066/OmniChat.git
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

**OpenAI (2026):**
- GPT-5.2 - Flagship model with reasoning_effort support for complex tasks
- GPT-5 Mini - Fast and cost-efficient for well-defined tasks
- GPT-4o - Reliable multimodal model

**Anthropic (Claude):**
- Claude Opus 4.5 (claude-opus-4-5-20251101) - Most capable model
- Claude Sonnet 4.5 (claude-sonnet-4-5-20250929) - Balanced performance
- Claude Haiku 4.5 (claude-haiku-4-5-20250929) - Fast and efficient

**Google (Gemini 3 - Preview):**
- Gemini 3 Pro (Preview) - State-of-the-art reasoning with thinking controls
- Gemini 3 Flash (Preview) - Fast frontier-class performance

> **Note:** GPT-5.2 includes automatic reasoning_effort parameter (set to "medium" by default). Gemini 3 models include thinking controls via thinkingLevel parameter (Pro: "high", Flash: "medium").

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
- `modelUsed`: String? (e.g., "gpt-5.2")

## Implementation Details

### API Streaming

All services implement streaming responses using `AsyncThrowingStream<String, Error>` for real-time message delivery.

- **OpenAI**: Server-Sent Events (SSE) with `data:` prefixed JSON, reasoning_effort parameter for GPT-5.2
- **Anthropic**: SSE with `content_block_delta` events, API version 2023-06-01
- **Google**: Server-Sent Events with `?alt=sse` parameter, API key in `x-goog-api-key` header, thinkingConfig support for Gemini 3

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

## Latest Release

### v0.1.2 (2026-01-27) - LaTeX & UI Improvements

**Fixed:**
- LaTeX formulas now show horizontal scrollbar when window is too narrow
- Assistant messages now expand to fill available width on wider windows

**Added:**
- Provider-specific system prompts for consistent LaTeX formatting

See [CHANGELOG.md](CHANGELOG.md) for full release history.
