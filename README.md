# Head Copy CW Trainer
This is heavily inspired by the excellent CW trainer G4FON (https://www.g4fon.net/). I'm still learning CW myself and wanted something I could use on my phone. Much of the information in this help file is inspired by the info found on the G4FON site but modified for the layout of this app. 

I'm releasing this as open source. Source should be available here: https://github.com/jhnhnsn/cwtrainer

Bugs, ideas, fixes are all welcome. Share and enjoy!

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

### How It Works

1. **Start at full speed** - Choose your target speed (e.g., 20 WPM) and stick with it. Don't start slow and build up.

2. **Begin with two characters** - Set the Letters slider to 2. For your first sessions, you'll only practice two characters (K and M in the standard Koch order).

3. **Practice for 5 minutes** - Press Start and copy the characters you hear. Write them down on paper or say them to yourself for head copy practice.

4. **Check your accuracy** - After the session, compare what you copied with the text displayed on screen. Calculate your percentage of correct characters.

5. **Progress when ready** - When you achieve 90% accuracy or better, add the next character by increasing the Letters slider.

6. **Repeat** - Your accuracy will temporarily drop as you learn each new character, but it will rise again. Continue until you've mastered all 40 characters.

### Why This Method Works

- **Builds reflexes, not lookup tables** - By learning at full speed, you develop instant recognition rather than mentally translating each character.
- **Constant positive reinforcement** - After mastering your first two characters at full speed, you know you can do it. Each new character is proof of progress.
- **Efficient use of time** - You progress at your own pace, spending only the time needed for each character.
- **No plateau frustration** - Unlike starting slow and hitting a wall at 10 WPM, you're already copying at your target speed.

## Practice Modes

### Letters
Practice individual characters using the Koch method. Use the Letters slider to control how many characters are in your practice set. Characters are introduced in the standard Koch order, starting with K and M.

### Groups
Practice random groups of 2 to N characters (configurable with Max Group Size slider). Groups vary in length to ease the transition from random practice to real words. This mode is useful once you've learned several characters and want to practice copying continuous text.

### Words
Practice real words from three different word lists:
- **CW** - Common amateur radio words and abbreviations
- **English** - Common English words
- **Learned** - Words composed only of characters you've already learned

The Learned option is particularly useful as it lets you practice real words while still progressing through the Koch method.

### QSO
Practice copying simulated amateur radio contacts (QSOs). These follow the format of real on-air exchanges, including callsigns, signal reports, names, locations, and common phrases. QSOs are played line by line with visual separators between different contacts.

## Settings

Access settings by tapping the gear icon in the app bar.

### Speed Settings

- **Actual Speed** - The character speed in words per minute. This is how fast individual characters are sent. Default: 20 WPM.

- **Effective Speed** - The overall speed including spacing. When lower than actual speed, extra space is added between elements. Default: 15 WPM.

- **Effective Speed Mode**
  - **Farnsworth** - Adds extra space between characters. Good for learning character recognition.
  - **Wordsworth** - Adds extra space between words. Good for practicing word recognition and head copy.

### Audio Settings

- **Pitch** - The tone frequency in Hz. Adjustable from 350 Hz to 1500 Hz in 25 Hz increments. Default: 700 Hz. Choose a pitch that's comfortable for extended listening.

### Display Settings

- **Display Delay** - How long to wait (in milliseconds) before showing the text after it's been sent. A longer delay encourages head copy rather than reading along. Default: 400 ms.

### Session Settings

- **Session Length** - Practice session duration in minutes. Set to 0 for unlimited sessions. Default: 5 minutes. Five-minute sessions are recommended for consistent practice and progress tracking.

### Reset to Defaults

Restores all settings to their default values.

## Tips for Success

1. **Practice regularly** - Short, frequent sessions are more effective than occasional long ones. Daily 5-minute sessions will produce steady progress.

2. **Don't rush** - Only add a new character when you consistently achieve 90% accuracy with the current set. Patience here saves time in the long run.

3. **Use head copy** - Say each character to yourself after hearing it rather than writing it down. This builds the reflexive recognition needed for real-time copying.

4. **Some days are harder** - Your performance will vary day to day. Some characters will take longer to learn than others. This is normal and has nothing to do with intelligence.

5. **Progress to words and QSOs** - Once you've learned the full character set, practice with the Words and QSO modes to develop real-world copying skills. Pay attention to callsigns, locations, and numbers.

6. **Adjust the effective speed** - If you're struggling, try lowering the effective speed while keeping the actual speed the same. This gives you more time to process each character without changing how the characters sound.

## Building from Source

This is a Flutter application. To build:

```bash
# Get dependencies
flutter pub get

# Run in debug mode
flutter run

# Build for release
flutter build apk        # Android
flutter build ios        # iOS
flutter build windows    # Windows
flutter build macos      # macOS
flutter build linux      # Linux
```

## License

This project is open source. See the LICENSE file for details.

## Acknowledgments

- Koch method training approach heavily inspired by the G4FON Koch Trainer

