# Head Copy CW Trainer

An adaptive trainer for learning to copy Morse code (CW) **in your head** — the way real operators do on the air. Inspired by the excellent G4FON trainer, but rethought around one adaptive mode instead of manual drills.

I'm still learning CW myself and wanted something I could use on my phone. Open source — bugs, ideas, and fixes welcome. Share and enjoy!

Source: https://github.com/jhnhnsn/cwtrainer

## How to use it

1. Press **Start**. (Set your callsign first in **Settings** if you like — see below.)
2. Listen to the short bit of code. **Don't look** — the answer stays hidden.
3. After a brief pause, tap out what you heard on the on-screen CW keyboard and press **Enter**.
4. You'll see whether you were right and how fast you recognized it, and can hear it again. Press **Next** to continue.
5. When your recent copy is solid and quick, the app quietly introduces the next item — and speeds you up.

## Why it works this way

- **Type, don't write.** Writing each letter by hand while more code arrives overloads working memory and keeps you decoding letter-by-letter. Answering after a short buffer trains you to hold the sound in your head and "copy behind" — the way skilled operators do.
- **Real words and phrases, not random letters.** You start on the highest-value on-air chunks — `CQ`, `DE`, `73`, `UR RST 599`, `HW CPY?`, `TNX FER CALL` — because meaningful chunks are learned and recalled far better than random strings, and experts hear common words as a single sound-shape rather than spelling them out.
- **Frequency first.** A small set of prosigns, abbreviations, and common words covers most of a real QSO, so those come first for the biggest payoff.
- **Spaced repetition.** Items you miss come back sooner; items you nail come back later. Weak spots get the practice; mastered material doesn't waste your time.
- **Speed gate, not just accuracy.** The app watches *how fast* you recognize each item, not only whether you get it right. A correct-but-slow answer means you're still consciously decoding, so a new item won't unlock until you're recognizing the current material **instantly**. This breaks through the plateau that catches people who only chase accuracy.
- **Adaptive speed.** Characters are always sent at a steady target speed (you learn at speed from day one). The app then automatically tightens the spacing — making you effectively faster — as your recognition gets fast and accurate, and eases off if it starts to hurt. You never set a WPM slider; the app owns your pace.
- **The "too slow" bar** adapts to *your* recent speed, not a fixed number, so it tightens as you improve.
- **Let misses go.** If you don't catch something, take your best guess and move on. Getting the gist and continuing is exactly the skill real head copy needs.
- **Your own callsign.** It's the first thing you copy on the air, so — once set — the app teaches it early and mixes it into realistic exchanges.
- **It never runs out.** After the built-in material — alphabet, prosigns, exchanges, numbers-in-context, callsigns, and common words — the app keeps going, generating an endless stream of fresh random callsigns and short QSO exchanges (`W1ABC DE {your call} 5NN K`) so you stay sharp.

## Settings

- **Your Callsign** — trained early and woven into generated exchanges.
- **Pitch** — the tone frequency, for your comfort/hearing.
- **Session Length** — minutes per session (0 = unlimited).
- **Reset** — reset settings to defaults, or wipe all Copy progress and start fresh.

(There's no speed or difficulty setting — the app controls all of that adaptively. See "Copy behind" below.)

## Copy behind (the buffer)

Once you can recognize the core material **instantly**, the app starts adding a short silent pause between the audio and your prompt to answer. This trains **copying behind** — holding the sound in your head for a beat before you reproduce it, the way skilled operators lag a word or two behind a transmission. The pause grows as you stay accurate with it, up to about a word or two behind, then holds. It's fully automatic and only kicks in after you've built instant recognition — copying-behind is an advanced skill, so the app doesn't burden a beginner with it.

## Tips for success

- Practice a little, often. Short daily sessions beat occasional long ones — watch your streak fill in on the activity calendar.
- Don't stare at the bar. Aim to answer the instant you recognize the sound; the goal is reflex, not deliberation.
- Trust the app to pace you. If it isn't introducing new material yet, it's because you're not *quite* fast enough on what you have — that's the point.
