# Head Copy CW Trainer
This is heavily inspired by the excellent CW trainer G4FON (https://www.g4fon.net/). I'm still learning CW myself and wanted something I could use on my phone. Much of the information in this help file is inspired by the info found on the G4FON site but modified for the layout of this app. 

I'm releasing this as open source. Source should be available here: https://github.com/jhnhnsn/cwtrainer

Bugs, ideas, fixes are all welcome. Share and enjoy!

## Copy — the adaptive mode (start here)

**Copy** is the app's default mode and works differently from the classic Koch drills below. Instead of you dragging a slider and grading yourself on paper, Copy adapts to you automatically and trains you on **real on-air material from the very first session**.

### How to use it
1. Open **Copy** (the first tab) and press **Start**. No paper needed.
2. Listen to the short bit of code. **Don't look** — the answer stays hidden.
3. After a brief pause, a box appears. **Type what you heard** and press Enter (or Check).
4. You'll see whether you were right, how fast you answered, and hear it again if you want. Press **Next** to continue.
5. When your recent copy is solid, the app quietly introduces the next item.

### Why it's built this way
- **Type, don't write.** Writing each letter by hand while more code arrives overloads working memory and keeps you decoding letter-by-letter. Typing after a short buffer trains you to hold the sound in your head and "copy behind" — the way skilled operators do.
- **Real words and phrases, not random letters.** You start on the highest-value on-air chunks — `CQ`, `DE`, `73`, `UR RST 599`, `HW CPY?`, `TNX FER CALL` — because meaningful chunks are learned and recalled far better than random strings, and experts hear common words as a single sound-shape rather than spelling them out.
- **Frequency first.** A small set of prosigns, abbreviations, and common words covers most of a real QSO, so those come first for the biggest payoff.
- **Spaced repetition.** Items you miss come back sooner; items you nail come back later. Weak spots get the practice; mastered material doesn't waste your time.
- **Speed gate, not just accuracy.** Copy watches *how fast* you recognize each item, not only whether you get it right. A correct-but-slow answer means you're still consciously decoding, so a new item won't unlock until you're recognizing the current material **instantly** (about half a second). This is the key to breaking through the plateau that catches people who only chase accuracy.
- **Let misses go.** If you don't catch something, don't stop to puzzle it out — take your best guess and move on. Getting the gist and continuing is exactly the skill real head copy needs.
- **Your own callsign.** Set your callsign on the welcome screen (or later in **Settings → Your Callsign**). It's the first thing you copy on the air, so Copy teaches it early and mixes it into realistic exchanges.
- **It never runs out.** Once you've worked through the built-in material — the alphabet, prosigns, exchanges, numbers-in-context, callsigns, and common words — Copy keeps going, generating an endless stream of fresh random callsigns and short QSO exchanges (`W1ABC DE {your call} 5NN K`) so you stay sharp on real on-air copy.

You can reset all Copy progress anytime from **Settings → Reset Copy progress**.

The classic Koch modes below (Letters, Groups, Words, QSO) remain available as manual drills if you prefer paper-based practice or want to target something specific.

## Quick Start

### Get set up
Get a pen (or pencil) and paper and start this app on Letters

### Do a session
1. Start with "Letters" with slider set to "2"
2. The app will start playing the first 2 letters. Don't look at the screen.
3. Write down the letters you hear on the paper until the session ends.
4. At the end of the session compare what you wrote to the letters on the screen
5. Once you're able to get around 90% accuracy consistently move the slider up to 3 letters.

## The Koch Method

The Koch method is a proven technique for learning Morse code that builds reflexive responses to individual characters. Unlike traditional methods that start slow and gradually increase speed, the Koch method has you learn at your target speed from the very beginning.

## How It Works

1. **Start at full speed** - Choose your target speed (e.g., 20 WPM) and stick with it. Don't start slow and build up.

2. **Begin with two characters** - Set the Letters slider to 2. For your first sessions, you'll only practice two characters (K and M in the standard Koch order).

3. **Practice for 5 minutes** - Press Start and copy the characters you hear. Write them down on paper or say them to yourself for head copy practice.

4. **Check your accuracy** - After the session, compare what you copied with the text displayed on screen. Calculate your percentage of correct characters.

5. **Progress when ready** - When you achieve 90% accuracy or better, add the next character by increasing the Letters slider.

6. **Repeat** - Your accuracy will temporarily drop as you learn each new character, but it will rise again. Continue until you've mastered all 40 characters.

## Why This Method Works

- **Builds reflexes, not lookup tables** - By learning at full speed, you develop instant recognition rather than mentally translating each character.

- **Constant positive reinforcement** - After mastering your first two characters at full speed, you know you can do it. Each new character is proof of progress.

- **Efficient use of time** - You progress at your own pace, spending only the time needed for each character.

- **No plateau frustration** - Unlike starting slow and hitting a wall at 10 WPM, you're already copying at your target speed.

## Practice Modes

**Copy** - The adaptive, spaced-repetition mode described at the top of this guide. Type what you hear; the app adapts and unlocks new material as you gain instant recognition. This is the recommended default.

**Letters** - Practice individual characters using the Koch method. Use the Letters slider to control how many characters are in your practice set.

**Groups** - Practice random groups of 2 to N characters. Groups vary in length to ease the transition from random practice to real words.

**Words** - Practice real words from CW abbreviations, common English words, or words made only from learned letters.

**QSO** - Practice copying simulated amateur radio contacts, including callsigns, signal reports, names, and locations.

## Settings

**Actual Speed** - The character speed in WPM. This is how fast individual characters are sent.

**Effective Speed** - The overall speed including spacing. When lower than actual speed, extra space is added between elements.

**Farnsworth vs Wordsworth** - Farnsworth adds space between characters. Wordsworth adds space between words.

**Pitch** - The tone frequency (350-1500 Hz). Choose a pitch comfortable for extended listening.

**Display Delay** - How long to wait before showing text after it is sent. Longer delays encourage head copy.

**Session Length** - Practice duration in minutes. Set to 0 for unlimited sessions.

## Custom Files

You can customize the word lists, QSO content, and even this help file. Go to **Settings** and tap **Open custom files folder** to access your editable files. Use **Reset files to defaults** to restore the original versions.

- **cw-words.txt** - CW abbreviations and ham radio terms (one word per line)
- **common-english-words.txt** - Common English words (one word per line)
- **qsos.txt** - Practice QSO content (see format below)
- **HELP.md** - This help file (Markdown format)

### QSO File Format

QSOs are defined between `---QSO START---` and `---QSO END---` markers. Each line within a QSO block is played separately:

```
---QSO START---
CQ CQ CQ DE W1ABC W1ABC K
W1ABC DE K2XYZ K2XYZ KN
K2XYZ DE W1ABC GM UR RST 599 599
---QSO END---
```

### File Locations

- **Windows**: `%APPDATA%\com.example\head_copy_cw_trainer\assets\`
- **macOS**: `~/Library/Application Support/com.example.helloWorldApp/assets/`
- **Linux**: `~/.local/share/head_copy_cw_trainer/assets/`
- **iOS**: Files app → On My iPhone → Head Copy → assets
- **Android**: Use a file manager to browse app documents

## Tips for Success

- Practice regularly. Short, frequent sessions are more effective than occasional long ones.

- Don't rush. Only add a new character when you consistently achieve 90% accuracy.

- Use head copy. Say each character to yourself rather than writing it down.

- Some days are harder. Your performance will vary, and some characters take longer to learn.

- Progress to words and QSOs once you learn the full character set.
