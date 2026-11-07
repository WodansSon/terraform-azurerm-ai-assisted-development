# LLM Brand Icons

- Source: [Lobe Icons](https://github.com/lobehub/lobe-icons).
- Pinned commit: `8a1b2821bb768c484fe8da20c5e1838b6bf551a9`.
- Upstream directory: [`packages/static-svg/icons`](https://github.com/lobehub/lobe-icons/tree/8a1b2821bb768c484fe8da20c5e1838b6bf551a9/packages/static-svg/icons).
- License: MIT License; see the adjacent `LICENSE.txt`.
- Copyright: Copyright (c) 2023 LobeHub.

## Inventory

The inventory contains all 340 standard SVGs at the pinned commit, one per upstream AI provider, model, or tool brand. Only unsuffixed filenames are included; color, wordmark, localized-text, and alternate-brand variants are excluded. This is a reproducible upstream catalog snapshot, not a claim to enumerate every LLM in existence.

Each source SVG is unmodified and was verified against its upstream Git blob hash when imported. The OpenAI icon belongs to this family rather than the parent icon directory.

## Offline Generation

The adjacent `runtime.json` declares the runtime symbols and legal companion files. `hosted_copilot/tools/internal/workbench/New-WorkbenchLlmIconSprite.ps1` delegates to the same shared builder used by every icon family, without model-specific generation behavior or network requests. The manifest selects OpenAI, Claude, Gemini, and Grok for the runtime sprite. The preview continues to display all 340 vendored icons, with at most six columns.

Generation preserves native viewBoxes, source geometry, fragment IDs, fills, and fill rules. Upstream layout-only root styles are omitted; the two standard icons with root grayscale styling retain it as an SVG filter presentation attribute. Symbols use the `llm-` prefix. Missing declared source icons fail generation rather than producing incomplete runtime artwork.

## Runtime Branding

The UI resolves the effective configured model identifier through [the branding map](../../llm-brands.json), independently of CLI provider routing and availability. Duplicate or overlapping model prefixes are rejected by the chat consumer and covered by its tests, not by icon generation. Unknown or missing model names display the Codicons `question` symbol. Unmapped model names and effort remain visible; that fallback stays in the Codicons sprite rather than being copied into the LLM family. The fixed Copilot assistant identity remains unchanged.

## Brand Ownership

Brand names and marks belong to their respective owners. Inclusion does not imply endorsement or grant trademark rights.
