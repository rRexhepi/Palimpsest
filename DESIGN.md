---
version: alpha
name: Palimpsest
description: Palimpsest is a macOS + iOS reading app that pairs an audiobook with its ebook and plays them in sync. Its design language is antiquarian-modern: warm parchment surfaces, deep ink typography, restrained leather and amber accents, serif-first reading body with humanist sans chrome. The page is the protagonist; the UI recedes. Think hardback novel re-bound for a 2026 retina display, not a SaaS dashboard. Generous gutters, optical leading, real shadows on the page surface, paper-tinted backgrounds. Audio sync rendered as a quiet amber underline on the active sentence with a soft pulse on the active word. Annotations live as translucent fills in a small palette of muted natural tones (sage, rose, slate, plum, amber). No neon, no pure black, no pure white, no AI shimmer.
---

colors:
  # Light theme — warm parchment
  canvas: "#F4EFE6"
  canvas-cool: "#EDE8DD"
  canvas-deep: "#E2DBCB"
  ink: "#1F1A14"
  ink-soft: "#3D352A"
  ink-muted: "#6B6253"
  hairline: "#D9D0BD"
  hairline-soft: "#E5DDC9"
  hairline-strong: "#BFB39A"

  # Dark theme — book at night
  canvas-dark: "#1B1815"
  canvas-cool-dark: "#15120F"
  canvas-deep-dark: "#0E0C0A"
  ink-dark: "#E9E2D4"
  ink-soft-dark: "#C6BEAE"
  ink-muted-dark: "#8C8579"
  hairline-dark: "#3A332B"
  hairline-soft-dark: "#2A241D"

  # Brand accent — saddle leather
  accent: "#8B5A2B"
  accent-deep: "#6E4520"
  accent-soft: "#B68B5C"
  accent-dark: "#C99A6A"
  accent-deep-dark: "#A47C50"
  accent-soft-dark: "#D9B186"
  on-accent: "#FBF7EE"

  # Audio sync
  highlight-sentence: "#C7973F"
  highlight-word: "#F2DDA5"
  highlight-word-soft: "#FAEFCB"

  # Annotation palette — muted naturals only
  annot-amber: "#C7973F"
  annot-sage: "#9BAB8E"
  annot-rose: "#C09593"
  annot-slate: "#7A8794"
  annot-plum: "#9B7E92"

  # Semantic
  semantic-success: "#6E8E5C"
  semantic-warning: "#C7973F"
  semantic-error: "#A65454"

typography:
  # Reading face — system serif (New York on Apple platforms)
  chapter-display:
    fontFamily: "New York Serif"
    fontSize: 40px
    fontWeight: 600
    lineHeight: 1.20
    letterSpacing: -0.5px
    style: italic-eligible
  display:
    fontFamily: "New York Serif"
    fontSize: 32px
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: -0.3px
  title-1:
    fontFamily: "New York Serif"
    fontSize: 24px
    fontWeight: 600
    lineHeight: 1.30
  title-2:
    fontFamily: "New York Serif"
    fontSize: 20px
    fontWeight: 600
    lineHeight: 1.35
  body-reading:
    fontFamily: "New York Serif"
    fontSize: 17px
    fontWeight: 400
    lineHeight: 1.65
    notes: "The page text default. Generous leading. Optical kerning."
  body-reading-italic:
    fontFamily: "New York Serif"
    fontSize: 17px
    fontWeight: 400
    lineHeight: 1.65
    style: italic
  drop-cap:
    fontFamily: "New York Serif"
    fontSize: 56px
    fontWeight: 600
    lineHeight: 1.0
    notes: "Chapter-opening capital. 3-line hang."

  # Chrome face — system humanist sans (SF Pro Text on Apple)
  body:
    fontFamily: "SF Pro Text"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.45
  body-medium:
    fontFamily: "SF Pro Text"
    fontSize: 15px
    fontWeight: 500
    lineHeight: 1.45
  caption:
    fontFamily: "SF Pro Text"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.40
  footnote:
    fontFamily: "SF Pro Text"
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.35
  micro-caps:
    fontFamily: "SF Pro Text"
    fontSize: 11px
    fontWeight: 600
    lineHeight: 1.30
    letterSpacing: 1.5px
    transform: uppercase
    notes: "Chapter label, library section headers."
  button:
    fontFamily: "SF Pro Text"
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.30
  numeral-mono:
    fontFamily: "SF Mono"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.40
    notes: "Page numbers, timestamps, scrubber."

rounded:
  xs: 2px
  sm: 4px
  md: 6px
  lg: 10px
  xl: 14px
  pill: 9999px
  notes: "Tighter radii than typical SaaS. Bookish UI is closer to print, less pillowy."

spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  xxl: 32px
  xxxl: 48px
  section: 64px
  gutter: 56px
  notes: "gutter is the outer margin of the page surface. Generous, like a hardback."

shadows:
  page:
    value: "0 1px 2px rgba(31,26,20,0.06), 0 8px 24px rgba(31,26,20,0.08)"
    notes: "The book page floats slightly above the canvas."
  page-flip-trailing:
    value: "0 0 32px rgba(31,26,20,0.18)"
    notes: "Cast by the leaving page during transition."
  card:
    value: "0 1px 2px rgba(31,26,20,0.05), 0 2px 8px rgba(31,26,20,0.04)"
  popover:
    value: "0 4px 16px rgba(31,26,20,0.10), 0 12px 40px rgba(31,26,20,0.10)"

motion:
  page-transition:
    type: spring
    response: 0.45
    damping: 0.85
    duration-fallback: 320ms
    notes: "2D slide with shadow trail and slight parallax for v1. Real Metal page-curl is a v2 polish pass."
  highlight-pulse:
    type: ease-in-out
    duration: 220ms
    notes: "Soft fade-in/out on word-level highlight."
  fade:
    type: ease-out
    duration: 180ms

components:
  page-surface:
    backgroundColor: "{colors.canvas}"
    border: "1px solid {colors.hairline}"
    rounded: "{rounded.sm}"
    padding: "{spacing.gutter} {spacing.gutter} {spacing.xxxl}"
    shadow: "{shadows.page}"
    notes: "The book page itself. Subtle paper-grain texture (1-2% noise) is encouraged."

  page-number:
    typography: "{typography.numeral-mono}"
    textColor: "{colors.ink-muted}"
    placement: "bottom center, 24px from page edge"

  chapter-label:
    typography: "{typography.micro-caps}"
    textColor: "{colors.ink-muted}"
    placement: "top center of left page, 24px from page edge"

  highlight-sentence:
    underlineColor: "{colors.highlight-sentence}"
    underlineThickness: 1.5px
    underlineOffset: 4px
    notes: "Active sentence during audio playback."

  highlight-word:
    backgroundColor: "{colors.highlight-word-soft}"
    rounded: "{rounded.xs}"
    paddingX: 1px
    notes: "Active word during audio playback. Translucent overlay, never a solid fill."

  annotation:
    backgroundColor: "{colors.annot-amber} @ 22% opacity"
    rounded: "{rounded.xs}"
    notes: "Replace amber with any annot-* token. Always translucent, never solid."

  bookmark-ribbon:
    fillColor: "{colors.accent}"
    width: 18px
    height: 32px
    placement: "top edge of page, 32px from spine"
    shadow: "{shadows.card}"
    notes: "Real ribbon affordance — tapered notch at the bottom edge."

  audio-bar:
    backgroundColor: "{colors.canvas-deep}"
    topBorder: "1px solid {colors.hairline}"
    height: 64px
    padding: "{spacing.md} {spacing.xl}"
    contains: ["scrubber", "play-pause", "speed-control", "chapter-jump"]

  scrubber:
    trackColor: "{colors.hairline-strong}"
    fillColor: "{colors.accent}"
    thumbColor: "{colors.accent}"
    thumbDiameter: 12px
    height: 3px

  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.canvas}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: "10px 18px"

  button-accent:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: "10px 18px"
    notes: "Reserve for primary CTAs. Used sparingly — the page is the hero."

  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    border: "1px solid {colors.hairline-strong}"
    rounded: "{rounded.md}"
    padding: "10px 18px"

  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.ink-soft}"
    typography: "{typography.button}"
    rounded: "{rounded.sm}"
    padding: "8px 12px"

  card:
    backgroundColor: "{colors.canvas-cool}"
    border: "1px solid {colors.hairline}"
    rounded: "{rounded.lg}"
    padding: "{spacing.xl}"
    shadow: "{shadows.card}"

  input:
    backgroundColor: "{colors.canvas}"
    border: "1px solid {colors.hairline-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "10px 14px"

  divider:
    color: "{colors.hairline}"
    thickness: 1px

  toc-row:
    typography: "{typography.body}"
    textColor: "{colors.ink-soft}"
    activeTextColor: "{colors.ink}"
    activeAccent: "{colors.accent}"
    padding: "10px 16px"
    notes: "Table of contents row. Active row gets a 2px accent bar on the leading edge."

layout:
  reader-mac:
    columns: 3
    structure: "[ToC sidebar 280px] [page surface flex] [annotations rail 320px]"
    audioBarPlacement: "fixed bottom"
  reader-ipad:
    portrait: "single page + collapsible ToC drawer + bottom audio bar"
    landscape: "facing pages spread + annotations as floating popover"
  reader-iphone:
    structure: "single page + tab bar [Read | Audio | Notes]"
    audioBarPlacement: "tab-bar adjacent, swipe-up for full controls"

dos-and-donts:
  do:
    - "Let the page breathe. Generous gutters and leading."
    - "Use serif for body reading text without exception."
    - "Keep accent usage rare — the saddle brown is a signal, not decoration."
    - "Render highlights as translucent fills, never solids."
    - "Use system serif/sans on Apple platforms (New York, SF Pro). Free, beautiful, accessibility-tuned."
    - "Treat the audio bar as a quiet utility — it should feel like a hardback's slip-jacket band, not a media player."
  dont:
    - "Use pure black (#000) or pure white (#FFF). Always tinted toward warm ink or parchment."
    - "Use neon, electric, or saturated digital colors anywhere."
    - "Use sans-serif for the body reading text."
    - "Add AI shimmer, glow, or sparkle effects. Anywhere."
    - "Use emoji in UI chrome."
    - "Adopt SaaS-dashboard density. This is a reading app — surfaces are sparse."
    - "Use iOS-default system tint blue. The accent is saddle brown, not iOS blue."
    - "Animate aggressively. Every transition should feel like turning a page, not a Material ripple."
    - "Use Material elevation patterns. Shadows here are warm and subtle, modeled on real paper."

agent-prompt-guide:
  quick-reference:
    - "Background: {colors.canvas} (light) / {colors.canvas-dark} (dark)"
    - "Body text: {colors.ink} on parchment, set in New York Serif 17/28."
    - "Primary accent: {colors.accent} — used rarely, for primary CTAs and bookmarks only."
    - "Audio sync: amber underline on the active sentence ({colors.highlight-sentence}), soft amber fill on the active word ({colors.highlight-word-soft})."
    - "Annotation colors: pick from annot-amber / annot-sage / annot-rose / annot-slate / annot-plum. Always rendered at ~22% opacity."
  example-prompts:
    library-screen: "Generate a library grid for Palimpsest. Each book is a card showing the cover thumbnail, title in {typography.title-2}, author in {typography.caption} muted, and a thin progress hairline along the bottom edge in {colors.accent}. Background {colors.canvas}, cards on {colors.canvas-cool} with {shadows.card}. Use the gutter spacing — give the grid generous breathing room."
    reader-screen: "Generate the reading surface for Palimpsest. Single centered page surface ({components.page-surface}) on {colors.canvas-cool} background, with chapter label top-center in {typography.micro-caps}, page number bottom-center in {typography.numeral-mono}, body text in {typography.body-reading}. Active sentence has an amber underline; active word has a soft amber fill. Bookmark ribbon at top-right when present."
    audio-controls: "Generate the audio bar for Palimpsest. Fixed bottom, 64px tall, {colors.canvas-deep} background, top hairline. Play-pause button on the left, scrubber center with timestamps in {typography.numeral-mono}, speed control (0.75x / 1x / 1.25x / 1.5x) on the right as ghost buttons. No icons larger than 20px. No labels under icons."
