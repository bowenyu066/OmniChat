# Changelog

All notable changes to OmniChat will be documented in this file.

## v0.1.3 (2026-01-27) - Multimodal Support

**Added:**
- Image and PDF attachment support for all providers (OpenAI, Anthropic, Google)
- File picker with ⌘⇧A keyboard shortcut
- Drag-and-drop file attachment directly onto input area
- Paste (⌘V) support for clipboard images
- Attachment preview cards with remove button in input area
- Click-to-expand image viewer with zoom controls (50%-300%)
- PDF viewer with PDFKit integration showing page count
- Save/copy context menus for all attachments
- 20MB file size limit with user-friendly error messages
- Support for JPEG, PNG, GIF, WebP images and PDF documents
- New `Attachment` SwiftData model with cascade delete relationship
- `AttachmentPreviewView` for input preview cards (80x80px thumbnails)
- `AttachmentDisplayView` for message attachments with expandable viewer
- `PendingAttachment` helper struct for validation before persistence

**Changed:**
- Updated Anthropic API version from 2023-06-01 to 2024-10-22 (required for vision/document support)
- Message model now includes `attachments: [Attachment]` relationship
- ChatMessage protocol supports multimodal content with `ChatMessageContent` enum
- OpenAI service converts PDF pages to images (max 5 pages) for vision API
- Anthropic service uses native `document` type for PDFs
- Google Gemini service uses `inlineData` parts for images and PDFs
- MessageInputView now allows sending messages with attachments-only (no text required)

**Technical:**
- 3 new Swift files created: `Attachment.swift`, `AttachmentPreviewView.swift`, `AttachmentDisplayView.swift`
- 9 existing files modified for multimodal support
- All attachments stored inline as `Data` in SwiftData (no external file references)
- Base64 encoding used for API transmission
- Provider-specific content formatting (image_url, image, inlineData)

## v0.1.2 (2026-01-27) - LaTeX & UI Improvements

**Fixed:**
- LaTeX formulas now show horizontal scrollbar when window is too narrow
- Assistant messages now expand to fill available width on wider windows

**Added:**
- Provider-specific system prompts for consistent LaTeX formatting across ChatGPT, Claude, and Gemini

**Changed:**
- User message max width reduced to 500pt for better visual balance
- Disabled app sandbox for local development

## v0.1.1 (2026-01-27) - API Updates & Gemini Fix

**Updated:**
- OpenAI: Migrated to 2026 models (GPT-5.2, GPT-5-mini, GPT-4o)
- OpenAI: Added reasoning_effort parameter support for GPT-5.2 (default: "medium")
- Google Gemini: Updated to Gemini 3 models (gemini-3-pro-preview, gemini-3-flash-preview)
- Google Gemini: Fixed API key authentication (moved to x-goog-api-key header)
- Google Gemini: Added streaming support with ?alt=sse parameter
- Google Gemini: Implemented thinkingConfig with thinkingLevel parameter
- Google Gemini: Added support for thoughtSignature field in responses

**Fixed:**
- Gemini API returning empty responses (incorrect API key placement)
- Model references in preview views updated to new model names

**Removed:**
- Outdated OpenAI models: gpt-4.1, gpt-4.1-mini, o4-mini, o3-mini
- Outdated Gemini models: gemini-2.5-pro, gemini-2.5-flash, gemini-2.5-flash-lite

## v0.1.0 (2026-01-27) - Initial Release

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
- OpenAI: 3 latest models (GPT-5.2, GPT-5-mini, GPT-4o)
- Anthropic: 3 latest Claude models (Opus, Sonnet, Haiku 4.5)
- Google: 2 Gemini 3 preview models (Pro, Flash)

**Features:**
- Real-time streaming responses
- Secure API key management via Keychain
- Local conversation history
- Beautiful SwiftUI interface with custom avatars
- Model switching mid-conversation
- Code block copy functionality
- Mathematical formula rendering
