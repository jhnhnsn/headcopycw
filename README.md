# Head Copy

A CW (Morse code) trainer for learning to **copy in your head** — no paper, no lookup tables, no settings to fiddle with.

You press Start, listen, and type what you heard. The app watches how fast and how accurately you answer, then adapts: it tightens the spacing as you get quick, introduces new material only when you've earned it, and eventually inserts a deliberate pause between the audio and the prompt so you learn to hold a transmission in your head and copy behind — the way real operators do.

It runs on your phone, which is the point. Short daily sessions, wherever you are.

I'm releasing this as open source. Bugs, ideas, and fixes are all welcome. Share and enjoy!

## Quick start

1. Press **Start**. (Set your callsign in **Settings** first if you like — it gets trained early and woven into generated exchanges.)
2. Listen. **Don't look**; the answer stays hidden.
3. After a brief pause, type what you heard and press **Enter** (or tap **Check**).
4. See whether you were right and how fast you recognized it. Replay with **Hear it** if you want, then press **Next**.
5. When your copy is solid *and* quick, the app quietly adds the next item and speeds you up.

That's the whole loop. There is no lesson to pick and no difficulty to set.

## How this differs from Koch and from G4FON

This started as a G4FON-style Koch trainer and is no longer one. The differences are the substance of the app, so they're worth stating plainly:

| | Classic Koch / G4FON | Head Copy |
|---|---|---|
| Material | Individual characters in a fixed Koch order (K, M, …), then random groups | Real on-air material from the first minute — `CQ`, `DE`, `73`, `UR RST 599`, `HW CPY?` — with characters introduced *just before* the words that need them |
| Progression | You watch your own accuracy and move a "characters" slider by hand | The app promotes you automatically, per item, on measured accuracy **and** reaction time |
| Speed | You choose actual and effective WPM | You never set a speed. Characters are always sent at full speed; only the spacing adapts |
| Gating | Accuracy only (~90%) | Accuracy **and** instant recognition — a correct-but-slow answer doesn't advance you |
| Review | Linear; once learned, always in the pool | Spaced repetition — misses come back sooner, mastered items later |
| Response | Write it down on paper | Type it after the audio ends, with a growing silent buffer that trains copy-behind |
| Modes | Letters / Groups / Words / QSO, chosen manually | One adaptive mode that moves through those stages on its own |
| End of course | You finish the 40 characters | Never ends — a generator produces fresh callsigns and exchanges forever |

The Koch insight that survives here is the important one: **learn at full character speed from the very beginning.** Everything built around it is different.

## Why it works this way

- **Type, don't write.** Writing letter-by-letter while more code arrives keeps you decoding one character at a time. Answering after a short pause trains you to hold the sound in your head and *copy behind*.
- **Real on-air material.** You practice the highest-value chunks you'll actually hear. Meaningful chunks stick far better than random letters, and experts hear common words as a single sound-shape.
- **Speed, not just accuracy.** A new item won't unlock until you recognize the current material *instantly*. Gating on speed is what breaks the plateau that catches people who only chase accuracy.
- **Adaptive pace.** Characters are always sent at full target speed. The app tightens the spacing as you get fast and accurate, and eases off if it hurts.
- **Spaced repetition.** Weak spots get the practice; known material doesn't waste your time.
- **Let misses go.** Take your best guess and move on. Getting the gist and continuing is exactly the skill head copy needs.
- **Never runs out.** After the built-in material, the app generates an endless stream of fresh callsigns and exchanges (`W1ABC DE {your call} 5NN K`).

## The three phases

The app shows your position on a three-step progress bar:

1. **Recognition** — building instant, reflexive recognition of characters and short on-air chunks.
2. **Copy behind** — once 15 items are mastered, a silent pause appears between the audio and the prompt. It starts at 400 ms and grows to about 2 seconds (a word or two) as you stay accurate, easing off if you struggle.
3. **On the air** — the fixed curriculum is exhausted and the generator takes over with endless callsigns and QSO exchanges.

## What it trains

215 items, introduced in order but only once their prerequisite characters are mastered:

- **The contact basics** — prosigns and skeleton: `CQ`, `DE`, `K`, `R`, `TU`, `AR`, `SK`, `KN`, `BT`, `73`, `GM`, `OM`, `UR`, `HW`, `TNX`, `FB`, `599`, `5NN`, `RST`.
- **Exchanges & numbers** — formulaic phrases in context: `UR RST 599`, `HW CPY?`, `MY NAME IS`, `QTH IS`, `TNX FER QSO`, `HPE CU AGN`, `PWR 100W`, `AGE 44`.
- **Common words** — ~110 everyday English words, which also fills out the rest of the alphabet.
- **Callsigns** — varied real-world prefixes (`W1ABC`, `VE3RM`, `DL4DX`, `JA1QRS`, `VK2ANT`) including portable `/P` forms.

Your own callsign is injected early so you learn to recognize yourself being called.

Curriculum order is never revealed in the UI — locked items collapse into a single "N more to unlock" chip, and milestone nudges deliberately avoid naming what's coming next, so you're never primed for an item before you hear it.

## Under the hood

Details, if you're curious — none of this is exposed as a setting.

- **Character speed is fixed at 20 WPM.** Only the effective (Farnsworth) speed adapts, starting at 15 WPM and moving between 8 and 20 in 1 WPM steps at the end of each session. It tightens at ≥90% accuracy with a median latency ≤550 ms, and eases below 75%.
- **Mastery** requires at least 3 recent reps, ≥90% rolling accuracy, and a *median* recognition time ≤550 ms. Promotion to new material uses a slightly lower bar plus a settling rule, so you only ever learn one new thing at a time.
- **Recognition time is measured at your first keystroke**, not at submit — typing speed is motor, not perceptual, and shouldn't count against you.
- **Spaced repetition** uses six Leitner boxes measured in reps rather than wall-clock time. A correct-and-fast answer promotes; correct-but-slow holds; a miss drops you two boxes.
- **Confusable pairs** are tracked per character. Fumble an `S` inside a word and its Morse neighbours (`I`, `H`, `U`) get preferentially resurfaced for discrimination practice.
- **The elapsed bar** under the input adapts to your own recent response times. It's motivational only — it never auto-submits, and finishing a slow answer still counts.
- **Daily dose** — past about 30 minutes in a day, the session recap gently suggests coming back tomorrow. It's a nudge, never a block.

Progress persists to a JSON file in the app's documents directory, with debounced writes and an immediate flush at session end. A corrupt or missing file degrades to empty progress rather than crashing. (On web, progress is in-memory only and does not persist.)

## Settings

There are only three:

- **Your Callsign** — trained early and woven into generated exchanges.
- **Pitch** — 350–1500 Hz in 25 Hz steps, default 700 Hz. For your comfort and hearing.
- **Session Length** — 5 / 10 / 15 minutes or a custom value; 0 means unlimited. Default 5 minutes.

Plus **Reset to defaults** and **Reset Copy progress** (which wipes all learning history and starts you fresh).

There is deliberately no speed, difficulty, or character-count setting. The app controls all of that adaptively.

## Tips

- Practice a little, often. Short daily sessions beat occasional long ones.
- Don't stare at the bar. Aim to answer the instant you recognize the sound: reflex, not deliberation.
- Trust the pace. If new material isn't appearing yet, it's because you're not *quite* fast enough on what you have — and that's the point.

## Building from source

A Flutter app (Dart SDK 3.x). Android and iOS are the primary targets; desktop and web build but are less polished.

```bash
flutter pub get
flutter run

flutter build apk        # Android
flutter build ios        # iOS
flutter build macos      # macOS
flutter build windows    # Windows
flutter build linux      # Linux
```

Run the tests:

```bash
flutter test
```

The test suite covers the adaptive engine fairly thoroughly — mastery and promotion gating, speed and buffer adaptation, spaced-repetition scheduling, simulated multi-session learner journeys, persistence across restarts, the endless generator, and the anti-priming rule that milestone nudges never name an upcoming item.

## License

Open source — see the LICENSE file for details.

## Thanks

Thanks to G4FON (<https://www.g4fon.net/>), whose Windows trainer got many of us started and inspired this project. This app takes a different path — one adaptive, head-copy-first mode — but owes a lot to it.
