# Visual Studio Code Codicons

The SVG files in this directory are selected icons from
[Microsoft's Visual Studio Code Codicons](https://github.com/microsoft/vscode-codicons)
at commit `1c47ab36a4bb845c437866405c2fa67b8ca0fe36`.

Copyright Microsoft Corporation. Licensed under the
[Creative Commons Attribution 4.0 International license](LICENSE.txt).

The adjacent `runtime.json` declares the exact symbols included in `sprite.svg` and the runtime legal notices. `preview.png` shows all adjacent source SVGs. The shared [New-WorkbenchSprite.ps1](../New-WorkbenchSprite.ps1) generates both assets for legacy and New Workbench consumers.

The source inventory includes all 14 Copilot-family icons present at the pinned commit. Their native 12px, 16px, and 50px viewBoxes and source geometry are preserved in the preview; only manifest-declared runtime icons enter the sprite.

The pinned `debug-restart` glyph represents restoring the original assessed rule proposal in Candidate Details and its confirmation dialog.

The pinned `debug-restart-frame` glyph is available in the runtime sprite for dialog-reset controls, preserving its native 16px viewBox and upstream geometry.

The pinned `git-branch`, `circle-slash`, and `warning` glyphs are available in the runtime sprite for native 16px status-bar previews. Their compact counterparts remain available for existing consumers; none of the source geometry is rescaled or redrawn.

The inventory includes all 17 `edit`, `terminal`, and `tools` family glyphs at the pinned commit, including compact and terminal-platform variants. Compact variants retain native 12px viewBoxes, `terminal` retains its native 24px viewBox, and the remaining family members retain native 16px viewBoxes. Their source geometry is preserved without rescaling.

The inventory includes all 21 `layout` family glyphs at the pinned commit, including `layout-sidebar-right`, `layout-sidebar-right-off`, and the docking variants. Their native 16px viewBoxes and source geometry are preserved without rescaling.

`open-in-window.svg` is included in the generated sprite. `link-external.svg` is retained as source artwork only and is not included in the sprite or runtime staging. Both preserve the pinned upstream geometry.

The pinned `git-pull-request-done` glyph is included in the runtime sprite for success-banner presentation, preserving its native 16px viewBox and upstream geometry.

The Workbench-authored `discard-all` and `collection-issues-compact` derivatives live in the separate [custom family](../custom/ATTRIBUTION.md), not this upstream inventory or sprite.

All adjacent source SVG files preserve the selected upstream geometry.
