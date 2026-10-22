# README structure and references

Reviewed on 2026-10-22. The examples below informed information hierarchy and navigation. Their prose, logos, screenshots, and project claims were not copied.

| Reference | Observed pattern | Applied to Codex Island |
| --- | --- | --- |
| [Ghostty](https://github.com/ghostty-org/ghostty/blob/main/README.md) | Clear product positioning and short links to download, documentation, and contributing | A concise first-screen description and direct navigation to the sections visitors need |
| [Mole](https://github.com/tw93/Mole/blob/main/README.md) | Visible language switcher, feature summary, early quick start, and expandable secondary setup | Reciprocal language links, source-build instructions before deep technical detail, and collapsed demo/diagnostics |
| [OpenCode](https://github.com/anomalyco/opencode/blob/dev/README.md) | Strong visual identity, prominent translations, and an explicit independence statement for related projects | Shared local banner, four consistent README editions, and a short OpenAI independence statement |
| [Tauri](https://github.com/tauri-apps/tauri/blob/dev/README.md) | Introduction, getting started, features, platform information, and links to deeper docs | Separate compatibility information and a documentation index instead of architecture detail on the front page |

## Editorial choices

The README should answer, in order: what this is, why it is useful, how to run it, how to use it, and what its current limits are.

- Keep the brand banner; remove the Water text from the image as requested. Credit the creator in prose.
- Use a short product description, verifiable features, static platform/license/preview badges, and a compact usage table.
- Put exact benchmark numbers, validation counts, parser limits, and publication instructions in their existing technical guides.
- Describe the actual source build. Do not invent a download link, Homebrew package, release badge, star count, or successful remote CI result.
- Keep experimental approval recognition distinct from recognized question waits. Do not claim unread, cloud, remote, or complete pet-state coverage.
- State the privacy behavior in reader language while linking the detailed policy.
- Use English as the canonical overview; keep Simplified Chinese, Traditional Chinese, and Japanese editions under `docs/`.
- Identify Chinese technical guides clearly so readers know what a link leads to.

These are editorial adaptations to this project's current capabilities, not an endorsement or a claim that other projects use the same architecture. Existing [asset and trademark boundaries](../THIRD_PARTY_NOTICES.md) still apply.
