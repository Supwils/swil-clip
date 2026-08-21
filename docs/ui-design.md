# SwilClip — UI Design System ("Brushed Quartz")

> ### v2 (Swift) — two recorded deviations, 2026-08-20
>
> This document stays canonical and every other token ports value-for-value into
> `swift/Sources/SwilClip/Design/Tokens.swift`. Two things changed, both recorded
> here because §7 says ratified values need sign-off:
>
> 1. **Typeface: SF Pro, not Geist** (§5.7). Geist was a web-era workaround for a
>    WebView that could not reach SF at variable weights; a native app can. This
>    document's own reference points — Spotlight and Raycast — are SF Pro, so the
>    change moves *toward* the stated intent. It also satisfies §5.7's actual
>    purpose (no network fetches, works offline) with **fewer** fonts, no bundled
>    asset and no font-registration code.
>
> 2. **Action cluster: 88 pt, not 66** (§5.2, §7). The 66 was correct arithmetic
>    for a **three**-action row: 3 × 20 + 2 × 2 gap + 2 breathing. v2's rows carry
>    a **fourth** action — "save as prompt" — so the same formula yields 88. The
>    rule is unchanged and now *computed* (`Token.Space.actionCluster(buttons:)`)
>    rather than hardcoded, so adding an action can no longer silently
>    under-reserve and let buttons sit on top of truncated text — the exact
>    failure §5.2 exists to prevent.
>
> Everything else — the six-step luminance scale, 12/10/2 pt spatial system,
> 11.5 pt row text, 4 pt row padding, 20 pt chip, 9.5 pt timestamp — is unchanged.

**Status:** Canonical. The user has explicitly approved this aesthetic
direction. Changes to spacing, typography, color, or component structure
need their sign-off — bug fixes that preserve the look are fine.

This document is the single source of truth for visual + interaction
decisions. When in doubt, match what's here, not what looks good in
isolation. Consistency >> local cleverness.

---

## 1. Aesthetic direction

**Brushed Quartz** — refined macOS-native, dense yet breathable, keyboard-first.
The reference points are Spotlight and Raycast: cool dark glass, hairline
separators, hierarchy built from luminance + weight rather than color. The
cool-azure accent is reserved for **selection + brand moments only**. Every
other surface lives in a calibrated gray scale.

Core principles, in priority order:

1. **Hierarchy via luminance, not chroma.** Six levels of foreground gray
   (`foreground / strong / muted / subtle / faint`). Color is for selection.
2. **Density with breathing room.** The panel is 340×480. Every pixel matters.
   Use a 4pt baseline grid. Don't waste vertical space, but don't crowd.
3. **Keyboard is the source of truth.** Mouse hover should never hijack
   keyboard cursor (we disable cmdk's pointer-selection for this reason).
   Mouse drag and click are *assistive*, never primary.
4. **No surprises in motion.** Apple-style spring curves (`cubic-bezier(0.32,
   0.72, 0, 1)`) — never bounce, never elastic. Always gated by
   `prefers-reduced-motion`.
5. **Restraint over decoration.** A hairline separator beats a colored
   divider. A 1px inner highlight beats a drop shadow. Glass beats fills.

If a change feels like it adds personality at the cost of one of these, it
fails the design.

---

## 2. Design tokens (CSS variables)

All tokens live in `src/global.css` under `@theme {}`. **Never hardcode a
color, radius, or font** — pull from a token. If you need a new value,
add a token first.

### 2.1 Surfaces (background layers)

| Token | Value | Role |
|---|---|---|
| `--color-background` | `hsl(220 20% 6% / 0)` | App-level fallback (transparent) |
| `--color-surface` | `hsl(220 22% 11% / 0.72)` | Main panel background |
| `--color-surface-soft` | `hsl(220 18% 16% / 0.55)` | Icon chips, nested cards |
| `--color-surface-hover` | `hsl(220 16% 22% / 0.55)` | Row hover bg |
| `--color-surface-active` | `hsl(214 64% 52% / 0.16)` | Selected row bg |
| `--color-surface-sunk` | `hsl(220 28% 6% / 0.55)` | Inputs, code blocks |

### 2.2 Foregrounds (luminance scale)

Each step has a **role**. Don't pick a step because it "looks right" —
pick the role.

| Token | Role |
|---|---|
| `--color-foreground` | Primary text (clip preview, dialog body) |
| `--color-foreground-strong` | Brand wordmark, hero numerals (rare) |
| `--color-foreground-muted` | Secondary labels (settings labels) |
| `--color-foreground-subtle` | Tertiary captions |
| `--color-foreground-faint` | Placeholder, timestamps, decorative |

### 2.3 Borders

| Token | Role |
|---|---|
| `--color-border` | App-shell outer hairline |
| `--color-border-subtle` | Divider rules, input borders |
| `--color-border-strong` | Hover/focus border emphasis |

### 2.4 Accent

| Token | Role |
|---|---|
| `--color-accent` | Selected-row rail, focus ring, drop indicator |
| `--color-accent-soft` | Selected icon chip tint |
| `--color-accent-muted` | Accent backgrounds for soft states |

**Never** use accent for body text or decorative purposes. It MUST mean
"this is selected" or "this is the active brand mark."

### 2.5 Spatial system

| Token | Value | Role |
|---|---|---|
| `--px-edge` | `12px` | Outer horizontal inset on the panel |
| `--px-row` | `10px` | Inner horizontal padding on list rows |
| `--gap-row` | `2px` | Vertical gap between rows |

Header, footer, and list MUST use these tokens — never raw `px-3` etc.

### 2.6 Radii

| Token | Value | Where |
|---|---|---|
| `--radius-xs` | 4px | Keycaps, swatches |
| `--radius-sm` | 6px | (reserved) |
| `--radius-md` | 8px | Buttons, input groups |
| `--radius-lg` | 10px | (reserved) |
| `--radius-xl` | 14px | App shell |

### 2.7 Motion

| Token | Curve |
|---|---|
| `--ease-spring` | `cubic-bezier(0.32, 0.72, 0, 1)` (Apple-style) |
| `--ease-out` | `cubic-bezier(0.2, 0.8, 0.2, 1)` |

Animations are always 100–200ms. Anything longer reads as sluggish for a
utility used dozens of times per day.

---

## 3. Typography

**Body:** `Geist Variable` (bundled via `@fontsource-variable/geist`, NOT
loaded from a CDN).
**Mono:** `ui-monospace`, falling back to SF Mono on macOS.

Type scale (compact, since panel is tiny):

| Use | Size / Weight |
|---|---|
| Clip preview body | 11.5px / 400 / leading 1.3 |
| Image dimensions | 9px / 400 |
| Timestamp + meta | 9.5px / 400 / tabular-nums |
| Group heading | 9px / 600 / uppercase / 0.09em tracking |
| Brand wordmark | 10.5px / 600 / tight tracking |
| Count badge | 8.5px / 500 / tabular-nums |
| Kbd keycap | 9px / 500 / mono |
| Settings section label | 11px / 600 / uppercase |

Rules:

- `tabular-nums` ALWAYS on numerics (timestamps, counts, shortcuts).
- `truncate` ALWAYS on single-line preview text; **the truncation point
  must reserve 66px on the right for the action overlay** (see §5.2).
- Use `feature-settings: "ss01", "cv01", "cv11"` globally (Geist
  stylistic alternates) — adds subtle character without compromising
  readability.

---

## 4. Components

### 4.1 App shell (`.app-shell`)

- Border radius: `--radius-xl` (14px)
- Background: linear gradient on top of `--color-surface` for depth
- Border: layered — outer hairline + inset highlight + drop shadow
- `backdrop-filter: blur(28px) saturate(150%)` — the glass effect
- A 1px gradient `::before` at the top edge for the "edge glow"
- Mount animation: 180ms spring scale-up + translate-Y(-2px → 0)

### 4.2 Drag region

20px tall strip at the top. Invisible by default. On `:hover` of the app
shell, three centered dots fade in as a quiet drag affordance. NEVER show
an always-visible drag handle here — the dots are enough.

### 4.3 Clip row (`.clip-item`)

- Padding: `4px var(--px-row)`
- Radius: `--radius-md` (8px)
- Total height: ~24px text + 8px padding ≈ 32px
- Selected state: `--color-surface-active` + inset 0.5px accent ring + 2px
  accent rail on left edge
- Hover state (not selected): `--color-surface-hover`
- Drag state: source row drops to opacity 0.3 + scale 0.985; non-target
  rows drop to opacity 0.45; drop target shows a 3px accent line w/ glow

The row is `draggable={true}` as a whole when reorder is enabled. HTML5
DnD only fires on actual movement, so click-to-paste is unaffected. Action
buttons inside the row are `draggable={false}` + `onDragStart`
preventDefault'd to keep them passive.

### 4.4 Type chip (`.clip-icon`)

20×20 square with `--radius-sm` (~5px), `--color-surface-soft` background.
Houses a 12×12 lucide icon at `--color-foreground-muted`. When the row is
selected, the chip background becomes `--color-accent-soft` and the icon
becomes `--color-accent`.

### 4.5 Action buttons

20×20 square with subtle radius. Visible only on row hover or selected.
Three roles: pin (left), expand (middle, conditional), delete (right).
The action cluster is absolute-positioned over the static meta cluster,
which has `min-width: 66px` reserved on the parent so text NEVER overlaps.

### 4.6 Group heading (`[cmdk-group-heading]`)

Uppercase, 9px, 0.09em tracking. Prefixed with a 2.5px filled dot.
Padding `4px var(--px-edge) 2px`.

### 4.7 Keycap (`kbd`, `.kbd`)

14×14 minimum, 3px corner radius, `--color-surface-soft` background with
inset highlight (top) + inset shadow (bottom) — convex pill effect.
Font: mono, 9px, 500.

### 4.8 Footer

Single row. Left: tool buttons (Clear, Undo, Search). Right: keyboard
hint reel. Separated from the list by a hairline divider — never a solid
border.

---

## 5. Hard rules (don't break these)

### 5.1 Spacing

ALL outer horizontal insets MUST use `var(--px-edge)`. ALL row internal
insets MUST use `var(--px-row)`. Never `px-2`, `px-3`, etc. for these
positions.

### 5.2 Action overlay reservation

The right cluster on each clip row MUST have `min-width: 66px`. This is
non-negotiable — without it, action buttons overlap truncated text.
(Empirically derived: 3 buttons × 20px + 2px × 2 gap + 2px breathing = 66.)

### 5.3 Mouse never moves the keyboard cursor

The `Command` root MUST keep `disablePointerSelection`. The
"selection follows mouse" pattern fights keyboard-first workflows and
causes selection drift during async mutations (delete, pin).

### 5.4 Search input is conditionally rendered

The `CommandInput` is in the DOM **only when in search mode**. When not
searching, it must not exist — otherwise cmdk's setState side-effect
re-focuses the hidden input on every keypress, which breaks the keyboard
chain in some WebView configurations.

### 5.5 Selection initialized eagerly

`selectedValue` MUST be initialized lazily via `useState(() => ...)` so
the first paint already has a valid selection. Post-paint useEffect
initialization causes a flash where arrow keys do nothing.

### 5.6 Animations gated by reduced-motion

EVERY animation/transition declaration MUST be defeated by the
`@media (prefers-reduced-motion: reduce)` rule at the bottom of
`global.css`. We already have a blanket rule — don't bypass it with
inline `animation: ...` in component code unless you also add a per-
component reduced-motion override.

### 5.7 No new fonts

Geist (sans) + ui-monospace (mono). No CDN font fetches — ever. The app
must work offline.

---

## 6. When you're stuck

- **"Should this be bigger?"** Probably not. Density is a feature.
- **"Should this be colored?"** Almost certainly not. The accent is for
  selection. Everything else is a luminance step.
- **"Should I animate this?"** Only if it transitions between two real
  states (open/closed, hover/rest). Don't animate decoratively.
- **"Should I add a border?"** Try a hairline (0.5px) first. If that's
  not enough, you probably need a different surface, not a border.
- **"Should I use shadcn defaults?"** No. They're starting points; this
  doc is the destination.

---

## 7. Locked-in moments worth preserving

These specific details have been A/B'd live by the user and ratified. Don't
revisit without consent:

- 11.5px clip preview text (not 12, not 13)
- 4px row vertical padding (not 5, not 6, not 7)
- 20×20 icon chip (not 24, not 28)
- 9.5px timestamp (not 10)
- 66px reserved action cluster width
- The drop indicator is 3px tall with a glow + leading dot, NOT a solid bar
- Pinned items render with an inline pin icon in the meta cluster (always
  visible, not just on hover)
- The drag region's three-dot affordance only appears on app-shell hover


---

## 8. v2 additions (Swift)

Everything in §2 above is the **dark** palette and is unchanged — those values
were A/B'd and the Swift port is byte-identical (`AccentPaletteTests` pins the
azure to the same `#4D93F0` the CSS shipped). What v2 adds:

### 8.1 Light appearance

`Token.adaptive(dark:light:)` wraps `NSColor(name:dynamicProvider:)`, so one
declaration serves SwiftUI, the `NSVisualEffectView` behind it and the menu-bar
menu alike, with nothing to observe. `Appearance` (system / light / dark) is
pushed at `NSApp.appearance`; every window inherits it, including the vibrancy
material, which picks its own light or dark variant.

The light column is **not** an inversion. Flipping lightness around 50 yields
muddy greys and blue-tinted glass. Each value was chosen for its role on a light
ground — hover a shade *darker* than rest rather than lighter, borders that
darken, and a bevel highlight pushed much harder because a white sliver at 18 %
does not register on a white surface.

### 8.2 Accent is a hue, not a colour

§2.4's rule — accent means "selected" and nothing else — is enforced by giving
the user exactly one degree of freedom. Saturation stays 84 and lightness stays
62 (dark) / 48 (light); only the hue moves. Every choice therefore lands
somewhere the system already works.

`onAccent` is **derived**, not the `hsl(0 0% 100%)` the CSS hard-coded: at a
fixed 84/62 the hue alone swings the accent from navy to highlighter, and white
on lime is unreadable. WCAG relative luminance picks black or white.

### 8.3 The scrim goes over the glass

`backdrop-filter: blur(28px)` in §4.1 has no AppKit equivalent —
`NSVisualEffectView` picks a *material*, and there is no public blur radius. The
Swift port originally stacked the panel colour *behind* the vibrancy view, where
a `.behindWindow` effect hides it completely; the panel was only ever as opaque
as `.hudWindow` happened to be, and a bright window behind it bled through.

The tint now sits **on top of** the glass, and its alpha is a user setting
(`PanelTint`: sheer 0.55 / standard 0.78 / solid 0.94). That is the only real
answer to "the background does not cover a bright app", and it is what gives the
panel a contrast floor independent of what is behind it.


### 8.4 Keyboard focus is visible, and says what Return will do

`←`/`→` step through a row's buttons and `⏎` runs the one under the ring. Two
rules keep that safe rather than merely possible:

- The focused button carries an accent ring and wash — and the **trash carries a
  red one**. Focus and hover can be on two different buttons at once, so the
  ring is what says which one Return is aimed at.
- While a button is armed, the footer reel is replaced by what `⏎` currently
  means (`⏎ delete`), plus the way out (`⎋ back`). Arrow keys are only safe on a
  destructive button if the panel tells you before you press Return.

The top bar gets the same treatment when `↑` reaches it — and it is a band with
stops, not just the two tabs: `[Clipboard | Prompts] … + ⚙`. The `+` appears
only on Prompts, because a plus next to "Clipboard" would read as "add a clip".

This is what finally gives two panel-level actions a keyboard route: "new
prompt" was `n`-only with no button at all, and Settings was mouse-only. Both
are now `↑`, along, `⏎`.
