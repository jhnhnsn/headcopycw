# CW Trainer – User Interface

Overview of the app’s screens and controls.

---

## 1. Main Screen (CW Trainer / Koch)

### App Bar

- **Title:** “CW Trainer (Koch)”
- **Settings (gear icon):** Opens the Setup page.
- **⋮ (more-vert):** Popup menu with **“Tone & Hello World”** → opens the tone-demo screen.

### Body (column, 16 pt padding)

#### Speed / Mode Line

- Centered text:  
  **Effective: X WPM · Actual: Y WPM · Farnsworth** (or **Wordsworth**).

#### Practice Mode (SegmentedButton)

- **Chars** (text_fields icon) – one random learned character per play.
- **Groups** (grid_on icon) – random group of `groupSize` characters.
- **Words** (article icon) – random word from the built-in list.
- **QSO** (record_voice_over icon) – canned QSO phrases.

One segment is selected at a time.

#### Display (Echo) Area

- Fills the remaining vertical space.
- Rounded container, `surfaceContainerHighest` background, bordered.
- `SingleChildScrollView` with **selectable** text; `titleLarge`, monospace, medium weight.
- Placeholder **—** when empty; otherwise the received characters/words/groups/QSO lines.
- **Chars & Words:** space-separated on one line.
- **Groups & QSO:** each item on its own line.
- Auto-scrolls to the bottom as new text is appended (after the display delay).

#### Start / Stop

- Full-width **FilledButton** with play/stop icon and label **“Start”** or **“Stop”**.

---

## 2. Setup Page (full-screen)

### App Bar

- **← Back:** Closes without saving.
- **Title:** “Setup”
- **Save:** Applies changes and returns to the main screen.

### Body (SingleChildScrollView, 24 pt padding)

| Control | Type | Range / options |
|--------|------|------------------|
| **Actual speed (WPM)** | Slider | 5–40, step 1 |
| **Effective speed (WPM)** | Slider | 5–40, step 1 |
| **Effective speed mode** | SegmentedButton | Farnsworth \| Wordsworth |
| **Characters learned (Koch, 2–40)** | Slider | 2–40, step 1 |
| **CW pitch (Hz)** | Slider | 400, 500, 600, 700, 800, 900 |
| **Group size (for Groups mode)** | Slider | 2–10, step 1 |
| **Words: only learnt letters** | CheckboxListTile | on/off |
| **Display delay (ms) – when to show received text** | Slider | 0–5000, step 100 |

The page is a scrollable column and scales with the window.

---

## 3. Tone & Hello World Page

Reached from the main screen via **⋮ → Tone & Hello World**.

### App Bar

- **Title:** “Tone & Hello World”
- Back via the platform/AppBar back control.

### Body (centered column, 32 pt horizontal padding)

- **Frequency label** – e.g. `600 Hz` (`headlineMedium`, bold).
- **Pitch Slider** – 400–900 Hz in discrete steps; label shows current Hz.
- **Caption** – “CW sidetone (400–900 Hz)”.
- **Play tone** – `ElevatedButton`; plays a 0.5 s sine at the selected frequency.
- **Play Hello World in Morse** – `ElevatedButton`; plays “HELLO WORLD” in Morse at that pitch.

---

## 4. Theming and Layout

- **Theme:** `ColorScheme.fromSeed(seedColor: Colors.blue)`, Material 3.
- **Main screen:** Column; mode selector and display area flex; Start/Stop anchored at the bottom.
- **Setup:** Single scrollable column of sliders, segmented buttons, and one checkbox; adapts to window size.
- **Tone page:** Centered, fixed controls.
- Display text uses `fontFamily: 'monospace'`; the empty-state placeholder is `—`.
