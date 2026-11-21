---
name: Synthetic Intelligence Shell
colors:
  surface: '#101319'
  surface-dim: '#101319'
  surface-bright: '#36393f'
  surface-container-lowest: '#0b0e13'
  surface-container-low: '#191c21'
  surface-container: '#1d2025'
  surface-container-high: '#272a30'
  surface-container-highest: '#32353b'
  on-surface: '#e1e2ea'
  on-surface-variant: '#b9cacb'
  inverse-surface: '#e1e2ea'
  inverse-on-surface: '#2d3036'
  outline: '#849495'
  outline-variant: '#3b494b'
  surface-tint: '#00dbe9'
  primary: '#dbfcff'
  on-primary: '#00363a'
  primary-container: '#00f0ff'
  on-primary-container: '#006970'
  inverse-primary: '#006970'
  secondary: '#ffb5a0'
  on-secondary: '#601400'
  secondary-container: '#ff5625'
  on-secondary-container: '#541100'
  tertiary: '#f8f4ff'
  on-tertiary: '#1f00a4'
  tertiary-container: '#d8d5ff'
  on-tertiary-container: '#4a37fd'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#7df4ff'
  primary-fixed-dim: '#00dbe9'
  on-primary-fixed: '#002022'
  on-primary-fixed-variant: '#004f54'
  secondary-fixed: '#ffdbd1'
  secondary-fixed-dim: '#ffb5a0'
  on-secondary-fixed: '#3b0900'
  on-secondary-fixed-variant: '#872000'
  tertiary-fixed: '#e3dfff'
  tertiary-fixed-dim: '#c3c0ff'
  on-tertiary-fixed: '#100069'
  on-tertiary-fixed-variant: '#2f00e4'
  background: '#101319'
  on-background: '#e1e2ea'
  surface-variant: '#32353b'
typography:
  display-hero:
    fontFamily: Space Grotesk
    fontSize: 56px
    fontWeight: '600'
    lineHeight: 64px
    letterSpacing: -0.03em
  display-hero-mobile:
    fontFamily: Space Grotesk
    fontSize: 36px
    fontWeight: '600'
    lineHeight: 44px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '500'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Space Grotesk
    fontSize: 20px
    fontWeight: '500'
    lineHeight: 28px
  body-lg:
    fontFamily: Geist
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Geist
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Geist
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 18px
  label-lg:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.04em
  label-md:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.06em
  label-sm:
    fontFamily: JetBrains Mono
    fontSize: 9px
    fontWeight: '600'
    lineHeight: 12px
    letterSpacing: 0.08em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-md: 1.5rem
  gutter-lg: 2rem
  margin: 1rem
  margin-md: 2rem
  margin-lg: 3rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system embodies an advanced, hyper-personalized artificial intelligence interface operating at the intersection of precision computing and ambient ergonomics. The experience evokes calm omnipotence, high-bandwidth clarity, and immediate responsiveness. Users transition seamlessly between focused diagnostic states and high-throughput creative states.

The aesthetic fuses **Futuristic Minimalism** with **Atmospheric Glassmorphism**. UI surfaces mimic zero-friction optical layers suspended over deep void space. Rather than decorative complexity, visual energy stems from high-frequency luminous accents, crisp geometric boundaries, variable blurs, and tactile feedback states engineered for low-latency cognitive processing.

## Colors

The system employs a dual-state operational palette governed by the computational intent of the user:

- **Alpha Mode (Analytical & Ambient Monitoring):** Anchored by electric cyan (`#00F0FF`) as the primary emission color against deep obsidian foundations (`#080B10`). Glowing neon indigo (`#4D3BFF`) serves as secondary resonance for state transfers, subtle background fields, and container rim lighting.
- **G Mode (Overdrive & Generative Synthesis):** Activated during high-intensity cognitive output, generative modeling, and real-time execution. Radiant orange-red (`#FF4500`) replaces the primary accent, supported by neon coral highlights (`#FF6E40`) over deep ember charcoal (`#0D0502`).

Both modes share neutral dark tokens calibrated for OLED reproduction:
- Surface Substrate: `#040608` (Absolute Void)
- Surface Base: `#080B10` (Obsidian Default) / `#0D0502` (Ember Default)
- Surface Raised: `rgba(255, 255, 255, 0.04)` with backdrop-filter
- Surface Border: `rgba(255, 255, 255, 0.12)`
- Surface Focus Glow: Alpha Mode (`rgba(0, 240, 255, 0.45)`) / G Mode (`rgba(255, 69, 0, 0.45)`)
- Text High-Emphasis: `#F1F5F9`
- Text Low-Emphasis: `#64748B`

## Typography

The typographic hierarchy balances speculative engineering with ergonomic clarity. 

- **Display & Headlines (Space Grotesk):** Provides mechanical geometry, high legibility, and architectural precision for interface titles and mode switchers.
- **Body & Longform (Geist):** Handles synthesized answers, conversational prompts, and general feedback with minimal distraction and neutral cadence.
- **System Metrics & Labels (JetBrains Mono):** Dedicated to runtime values, latency meters, parameter inputs, telemetry stamps, and execution logs. 

All mono labels enforce uppercase transformation by default to maintain consistent technical density.

## Layout & Spacing

The interface employs a fluid, modular command grid built around a centralized telemetry canvas:

- **Desktop (12 Columns):** Multi-column HUD layout with variable command rails (3 columns), conversational workbench (6 columns), and state inspection console (3 columns). Gutters are locked to `gutter-lg` (`2rem`) with canvas margins set to `margin-lg` (`3rem`).
- **Tablet (8 Columns):** Collapsible inspection console transformed into a sliding glass sheet. Gutters default to `gutter-md` (`1.5rem`).
- **Mobile (4 Columns):** Single-column stacked feed anchored by a floating bottom prompt hub. Margin reduces to `margin` (`1rem`) to maximize content surface area.

All inner container gaps follow strict increments of `4px` (`space-xs` through `space-xl`), ensuring vertical alignment across dense modular tiles.

## Elevation & Depth

Visual hierarchy is constructed through luminosity and translucent optical refractive layers rather than standard shadow dropping:

1. **Layer 0 (Substrate Void):** Deep solid neutral canvas (`#080B10` or `#0D0502`). Non-interactive backdrop.
2. **Layer 1 (Frosted Glass Plate):** Background `rgba(255, 255, 255, 0.03)`, backdrop filter `blur(20px)`, subtle 1px border of `rgba(255, 255, 255, 0.08)`. Used for base panels, module docks, and cards.
3. **Layer 2 (Floating Instrument):** Background `rgba(255, 255, 255, 0.07)`, backdrop filter `blur(32px)`, border `rgba(255, 255, 255, 0.16)`. Accompanied by an ambient rim cast of active mode emission (`0 8px 32px -4px rgba(0, 240, 255, 0.15)` in Alpha; `0 8px 32px -4px rgba(255, 69, 0, 0.18)` in G Mode).
4. **Layer 3 (Overdrive Overlay & Modal):** Topmost tier with sharp inner rim lighting `inset 0 1px 1px 0 rgba(255, 255, 255, 0.3)` and intense focused glow projection around element perimeters.

## Shapes

The interface balances precision-machined edges with humanized tactile curvature. 

- Standard containers, glass cards, and code panels leverage `roundedness: 2` (base `0.5rem` / `8px`), offering disciplined structural boundaries.
- Larger diagnostic hubs, floating command bars, and dynamic overlays scale to `rounded-lg` (`1rem` / `16px`).
- Micro-controls, pills, status indicators, and mode switches utilize fully rounded capsule boundaries (`9999px`) to immediately denote high-priority tactile interactions.

## Components

### Buttons & Interactive Triggers
- **Primary Action:** Solid glowing core in current mode accent (Electric Cyan or Radiant Red-Orange) with high-contrast dark text (`#040608`). Dynamic outer bloom on hover (`box-shadow: 0 0 24px var(--accent-glow)`). Micro-scale compression (`transform: scale(0.98)`) on physical click.
- **Secondary Action:** Glass plate button (`rgba(255, 255, 255, 0.05)`) with a 1px perimeter border. Label rendered in monospaced or Geist text; glows slightly on focus.
- **Ghost/Tertiary:** Unbordered transparent surface with label lighting up on cursor hover.

### Inputs & AI Command Bar
- **Prompt Field:** Ultra-thin glass capsule (`backdrop-filter: blur(24px)`, `background: rgba(12, 16, 24, 0.6)`). Border transitions from subtle gray to mode-reactive neon stroke on active input. Left-aligned glowing prompt indicator (`>_`).
- **Telemetry Slider & Range:** Hairline horizontal track with an ultra-bright point light head. The filled region emits a low-blur gradient trail.

### Cards & Panels
- Constructed with frosted glass layers. Header areas incorporate mono-spaced micro metadata (e.g., `LATENCY // 12ms`, `SYS.STATE // ACTIVE`). Borders feature variable opacity, brightening towards top-left to mimic a directional light source.

### Selection Controls (Toggles, Radios, Checkboxes)
- **Mode Toggle Switch:** Dual-state segmented glass pill. Sliding magnetic puck that transitions between glowing cyan pill (Alpha) and incandescent orange pill (G Mode).
- **Checkboxes & Radios:** Sharp geometric micro-boxes (`16px`) with illuminated inner neon targets upon selection.

### AI Waveform & State Orbs
- Ambient floating orbs and audio reactive spectrum lines that shift wavelength, frequency, and particle dispersion between electric cyan/indigo (Alpha Mode) and fiery red/coral (G Mode).