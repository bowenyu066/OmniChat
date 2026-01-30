# Changelog

All notable changes to OmniChat will be documented in this file.

## v0.2.3-beta (2026-01-30) - UI Fixes

**Fixed:**
- Workspace Panel: Sidebar selection now works properly (removed blocking tap gesture)
- User messages now have a copy button (same as assistant messages)
- Memory auto-select: Fixed predicate for finding auto-selected memories

## v0.2.2-beta (2026-01-29) - Critical Bug Fixes & Bulk Delete

**Fixed:**
- **Critical:** Messages no longer disappear after sending (SwiftData persistence fix)
- **Critical:** Messages now go to the correct conversation (SwiftUI view identity fix with `.id()` modifier)
- "Pin to top" now actually brings pinned memories to the top of the list
- Workspace Panel toolbar layout fixed (New Workspace button was hidden)

**Added:**
- Bulk delete for Memory Panel: Edit mode with Select All checkbox and Delete Selected button
- Bulk delete for Workspace Panel: Same functionality for managing workspaces
- Selection counter shows number of items selected in edit mode

**Changed:**
- Memory rows hide individual Edit button when in bulk edit mode
- Context menus disabled during edit mode for cleaner UX

**Technical:**
- Messages now explicitly inserted into modelContext before relationship assignment
- Explicit `message.conversation = conversation` relationship binding
- Added `.id(conversation.id)` to ChatView to force view recreation on conversation switch
- Memory list now sorted with pinned items first, then by updatedAt

## v0.2.1 (2026-01-29) - Workspace Fixes & Native PDF Support

**Added:**
- Workspace deletion with right-click context menu and confirmation dialog
- Delete workspace works even during active indexing

**Fixed:**
- File indexing now properly persists indexed files to database (SwiftData relationship fix)
- Workspace deletion no longer crashes app (ID-based state management)
- WorkspaceDetailView no longer crashes when workspace is deleted
- Claude API now works correctly (API version set to `2023-06-01`)
- Claude Haiku 4.5 model ID corrected (`claude-haiku-4-5-20251001`)

**Changed:**
- Native PDF support for all providers (no more image conversion):
  - OpenAI: Uses `type: "file"` with `file_data` (native PDF, up to 100 pages)
  - Anthropic: Uses `type: "document"` with base64 (native PDF)
  - Google: Uses `inlineData` with `application/pdf` (native PDF)
- Workspace views rewritten with ID-based lookup to prevent SwiftData invalidation crashes
- Anthropic API version updated from `2024-10-22` to `2023-06-01` (standard version)

**Technical:**
- FileIndexer: Changed relationship assignment from `entry.workspace = workspace` to `workspace.fileEntries.append(entry)`
- WorkspacePanelView: Uses `selectedWorkspaceID: UUID?` instead of `selectedWorkspace: Workspace?`
- WorkspaceDetailView: Queries workspace by ID, handles missing workspace gracefully
- OpenAIService: Removed PDF-to-image conversion, now sends native PDF
- Removed unused PDFKit import from OpenAIService

## v0.2.0 (2026-01-28) - Memory-First Design & UX Improvements

**Added:**
- Memory system with full CRUD operations for user knowledge persistence
- Memory Panel: Separate window for managing all memories (⌘M)
- Chat Memory Context: Right-side panel to control memory access per conversation
- Memory types: Facts, Preferences, Projects, Instructions, References
- Memory search and filtering by type, scope, pinned status, and tags
- Soft delete for memories with recovery support
- "Save to Memory" action on assistant messages
- Detailed customization window for fine-grained memory/conversation access control
- Message action buttons: Copy, Audio (TTS), Retry, Switch Model, Branch to New Chat
- Text-to-speech for AI responses using macOS NSSpeechSynthesizer
- Branch conversation feature to duplicate chat history up to a specific message
- Model switching with in-place response regeneration
- Retry button to regenerate responses with same model
- Auto-save API keys with 500ms debounce and visual feedback ("Saving...", "Saved")
- Session-based authentication for Settings (authenticate once per session)
- Keychain migration system to prevent repeated password prompts
- Authentication gate for Settings page with Touch ID/password fallback

**Changed:**
- Removed user/assistant avatars from messages for cleaner UI
- Removed "You" label from user messages (timestamp only)
- Title generation now only happens once after first assistant response
- Model selector moved to right side of chat header
- Sidebar now includes "Memory Panel" button at the bottom
- Auth flow simplified to single Touch ID/password prompt with automatic fallback
- Keychain access changed to `kSecAttrAccessibleAfterFirstUnlock` (no repeated prompts)
- API keys now display save status indicators (idle/saving/saved/error)
- Settings page requires one-time authentication per session (clears on exit)
- App startup authentication only required if 30+ days since last auth

**Removed:**
- Delete button from message actions (too dangerous, caused accidental deletions)
- Repeated title regeneration (now fixed after first response)
- Multiple keychain authentication prompts for API key reads

**Technical:**
- New models: `MemoryItem`, `MemoryType`, `MemoryScope`, `Workspace`
- New views: `MemoryPanelView`, `MemoryEditorView`, `MemoryFilterBar`, `MemoryRow`, `ChatMemoryContextView`
- Updated `AuthManager` with session-based settings auth and 30-day grace period
- Updated `KeychainService` with migration support and improved access settings
- Updated `Conversation` model with `hasTitleBeenGenerated` flag
- Memory Panel opens as separate window using SwiftUI Window scene
- Three-column layout with HSplitView for chat + memory context
- MessageActionBar component for assistant message actions
- SpeechService singleton for text-to-speech functionality

## v0.1.4 (2026-01-27) - AI Title Generation & App Improvements

**Added:**
- AI-powered conversation title generation using GPT-4o
- `TitleGenerationService` for automatic title generation from conversation context
- Title generation progress indicator in toolbar
- Custom app icons in all required sizes (16, 32, 64, 128, 256, 512, 1024px)
- In-memory API key caching in KeychainService to reduce keychain access
- Notification-based image paste handling for clipboard screenshots

**Changed:**
- Title generation now uses full conversation context (user + assistant messages)
- Re-enabled App Sandbox with proper entitlements (network.client, files.user-selected.read-only)
- Simplified system prompts (removed verbose LaTeX formatting instructions)
- Attachment button size increased from 24pt to 32pt for better visibility
- Replaced `onPasteCommand` with custom Command menu paste handler for reliable clipboard image handling
- Consolidated notification name definitions in OmniChatApp.swift

**Fixed:**
- Clipboard image paste now works reliably with screenshots
- Text paste no longer interfered with by image paste handler

**Technical:**
- New `TitleGenerationService.swift` with GPT-4o integration
- Added `isTitleGenerating` flag to Conversation model
- Keychain caching with `preloadKeys()` and `clearCache()` methods
- Moved `focusMessageInput` notification to app-level definitions

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
