# Changelog

All notable changes to OmniChat will be documented in this file.

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
