# Fluent System Icons Attribution

The adjacent 20px regular and filled SVG sources, generated `sprite.svg`, and generated `preview.png` are derived without geometry changes from Microsoft Fluent UI System Icons at commit `a347af95478f989038cccbf085978865264c048a`.

The local inventory contains 375 size-specific families and 750 icons. It includes the
application-semantic core below plus every complete 20px Regular/Filled pair
from the pinned upstream revision in these explicitly requested domains:

- Arrow: 150 families
- Board: 4 families
- Book and Bookmark: 31 families
- Bot: 3 families
- Brain: 3 families
- Branch: 8 families
- Bug: 3 families
- Chat: 25 families
- Chevron: 14 families
- Cloud: 21 families
- Code: 7 families
- Collections: 3 families
- Column: 7 families
- Comment: 20 families
- Content View: 3 families
- Dashboard: 1 family
- Link: 10 families

`Book Default` is excluded because the pinned upstream revision provides only
the Filled variant and this inventory requires complete Regular/Filled pairs.

The additional 16px Link Multiple, Link Dismiss, and Gauge Regular/Filled pairs
support compact status surfaces. Link Dismiss is the native-16px semantic
substitute for Link Off, which has no 16px upstream asset. Gauge Regular conveys
remaining Hosted guidance capacity.

The generated runtime `sprite.svg` contains only icons currently consumed by
the Workbench. The generated `preview.png` renders the complete vendored source
inventory so maintainers can inspect every available local icon.

The rule-action confirmation's inline two-tone question-circle glyph reuses the
pinned `Question Circle 20 Color` geometry with Workbench-owned flat dark-theme
colors instead of the upstream gradient fills.

The application-semantic core contains 20px regular and filled variants for:

## Status And Outcome

- Checkmark Circle
- Dismiss Circle
- Error Circle
- Important
- Info
- Question Circle
- Warning

## Governance And Trust

- Shield Checkmark
- Shield Dismiss
- Shield Error
- Shield Question
- Shield Task
- Approvals App
- Certificate

## Rule Document Lifecycle

- Document Add
- Document Bullet List
- Document Checkmark
- Document Dismiss
- Document Edit
- Document Error
- Document Lock
- Document Search
- Document Sync
- Document Text

## Assessment And Workflow Semantics

- Arrow Sync Circle
- Book Information
- Bot Sparkle
- Brain Circuit
- Clipboard Checkmark
- Clipboard Task List LTR
- Data Usage
- Gauge
- History
- Lightbulb
- Person Feedback
- Target Arrow

## Relationship Topology And Consolidation

- Arrow Routing
- Arrow Routing Rectangle Multiple
- Arrow Split
- Flow
- Flowchart
- Link Multiple
- Connected
- Group List
- Shape Intersect
- Merge
- Stack
- Stack Arrow Forward

## Maintainer Decisions And Governance

- Gavel
- Gavel Prohibited
- Scales
- Checkbox Checked Sync
- Flag Checkered
- Ribbon
- Ribbon Off
- Person Edit

## Lifecycle And Reconciliation Operations

- Archive
- Archive Arrow Back
- Arrow Undo
- Arrow Redo
- Arrow Sync Checkmark
- Arrow Sync Dismiss
- Re Order
- Document Copy
- Document Arrow Right

## Evidence And Inspection Operations

- Clipboard Search
- Clipboard Text LTR
- Text Quote
- Database Search
- Task List Square Sparkle
- Wand

Source: [microsoft/fluentui-system-icons](https://github.com/microsoft/fluentui-system-icons)

Fluent UI System Icons are distributed under the MIT License.
