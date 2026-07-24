/// The in-app help / guide, rendered as markdown on the WelcomePage's
/// "Full guide" screen (InfoPage). Kept as a Dart constant rather than a
/// bundled asset so it always tracks the build. An earlier asset-file approach
/// cached a stale copy in the app's documents directory and never updated.
const String kHelpMarkdown = r'''
## How to use it

1. Press **Start**. (Set your callsign in **Settings** first if you like.)
2. Listen. **Don't look**; the answer stays hidden.
3. After a brief pause, type what you heard and press **Enter** (or tap Check).
4. See whether you were right and how fast you recognized it; replay if you want. Press **Next**.
5. When your copy is solid and quick, the app quietly adds the next item and speeds you up.

## Why it works this way

- **Type, don't write.** Writing letter-by-letter while more code arrives keeps you decoding one character at a time. Answering after a short pause trains you to hold the sound in your head and *copy behind*, the way skilled operators do.
- **Real on-air material.** You practice the highest-value chunks you'll actually hear, like `CQ`, `DE`, `73`, `UR RST 599`, and `HW CPY?`. Meaningful chunks stick far better than random letters, and experts hear common words as a single sound-shape.
- **Speed, not just accuracy.** A new item won't unlock until you recognize the current material **instantly**. A correct-but-slow answer means you're still decoding, and gating on speed is what breaks the plateau that catches people who only chase accuracy.
- **Adaptive pace.** Characters are always sent at full target speed. The app tightens the spacing as you get fast and accurate, and eases off if it hurts. You never set a WPM.
- **Spaced repetition.** Misses come back sooner and mastered items later, so weak spots get the practice while known material doesn't waste your time.
- **Let misses go.** Take your best guess and move on. Getting the gist and continuing is exactly the skill head copy needs.
- **Never runs out.** After the built-in material, the app generates an endless stream of fresh callsigns and exchanges (`W1ABC DE {your call} 5NN K`) to keep you sharp.

## Copy behind (the buffer)

Once you recognize the core material instantly, the app adds a short silent pause between the audio and your prompt. This trains you to hold the sound in your head for a beat, the way skilled operators lag a word or two behind a transmission. The pause grows as you stay accurate, up to about a word or two, then holds. It's automatic and only starts after you've built instant recognition, so it never burdens a beginner.

## Settings

- **Your Callsign**: trained early and woven into generated exchanges.
- **Pitch**: the tone frequency, for your comfort and hearing.
- **Session Length**: minutes per session (0 = unlimited).
- **Reset**: restore default settings, or wipe all progress and start fresh.

There's no speed or difficulty setting; the app controls all of that adaptively.

## Tips

- Practice a little, often. Short daily sessions beat occasional long ones.
- Don't stare at the bar. Aim to answer the instant you recognize the sound: reflex, not deliberation.
- Trust the pace. If new material isn't appearing yet, it's because you're not *quite* fast enough on what you have, and that's the point.

## Thanks

Thanks to G4FON (<https://www.g4fon.net/>), whose Windows trainer got many of us started and inspired this project. This app takes a different path, one adaptive head-copy-first mode, but owes a lot to it.
''';
