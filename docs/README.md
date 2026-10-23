# Documentation

[Project home](../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md)

Choose a guide below. The README overview is available in four languages; most detailed engineering guides and repository policies are currently written in Simplified Chinese.

## Using Codex Island

| Guide | What you will find | Language |
| --- | --- | --- |
| [First-use and connection guide](getting-started.md) | Onboarding, grouped settings, recovery actions, and redacted diagnostics in unreleased source | 简体中文 |
| [Local session source](local-session-source.md) | Read scope, state mapping, compatibility, and diagnostics | 简体中文 |
| [Pet animation](pet-animation.md) | Runtime assets, timing, fallback, and animation behavior | 简体中文 |
| [Native state previews](assets/previews/README.md) | Eight state/display examples and reproducible native rendering | English |
| [Security and privacy](../SECURITY.md) | Local data, permissions, and vulnerability reporting | 简体中文 |

## Building and integrating

| Guide | What you will find | Language |
| --- | --- | --- |
| [Contributing](../CONTRIBUTING.md) | Toolchain, tests, and contribution expectations | 简体中文 |
| [Product and architecture](design.md) | UI behavior, components, and data flow | 简体中文 |
| [External status files](status-input.md) | The opt-in development input contract | 简体中文 |
| [Performance](performance.md) | Reproducible benchmarks and measurement limits | 简体中文 |

## Project status

| Guide | What you will find | Language |
| --- | --- | --- |
| [Release automation](releases.md) | Version tags, universal packages, checksums, and preview publication | English |
| [Release readiness](release-readiness.md) | Validation evidence, pending checks, and publication workflow | 简体中文 |
| [Integration findings](integration-findings.md) | Source decisions and observed compatibility | 简体中文 |
| [Implementation plan](implementation-plan.md) | Completed work and remaining validation | 简体中文 |
| [Changelog](../CHANGELOG.md) | Version notes | 简体中文 |
| [Brand assets](../Artwork/README.md) | Icon, banner, generation prompts, and provenance | 简体中文 |
| [Asset and trademark notices](../THIRD_PARTY_NOTICES.md) | Project branding and runtime third-party asset boundaries | 简体中文 |

<a id="readme-translations"></a>
## README translations

The English [root README](../README.md) is the source of truth for the project overview.

| Language | File |
| --- | --- |
| English | [README.md](../README.md) |
| 简体中文 | [docs/README.zh-CN.md](README.zh-CN.md) |
| 繁體中文 | [docs/README.zh-TW.md](README.zh-TW.md) |
| 日本語 | [docs/README.ja.md](README.ja.md) |

When changing the overview:

1. Update the English text and all three translations together. Translate for readers rather than word for word.
2. Preserve the same explicit section anchors (including `previews`) and all shell commands. Translate headings and navigation labels.
3. Keep language links reciprocal. Root assets use `docs/assets/`; translations use `assets/`. Root-level files need `../` from this directory.
4. Keep preview status, signing, source scope, privacy behavior, and unverified capabilities equivalent in every language.
5. Never turn a deployment target into a tested-platform claim, or a configured CI workflow into a passing-build claim.
6. Leave private images, session data, and `local/` outside the public file set. Banner artwork is branding, not a screenshot of the running app.
7. Keep all eight state-preview references and their translated captions / alt text aligned. Describe them as native view renders with synthetic content; do not claim screenshots or hardware validation.

Translation review should also check natural phrasing and terminology; structural checks alone do not establish translation quality. README translations cover documentation, not app UI localization.

For the reference projects and editorial choices behind the current layout, see [README design notes](readme-design.md).
