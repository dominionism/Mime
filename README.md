# Mime

**Touchless gesture control for macOS.**

Mime is a menu-bar app that watches for deliberate hand poses through your Mac's camera and turns them into actions: opening apps, websites and files, running Shortcuts and scripts, pressing keyboard shortcuts, and controlling media. The goal is a Mac you can drive with less reaching for the keyboard and mouse.

> [!NOTE]
> Mime is in early development. There's nothing to download or build yet.

## How it works

1. Turn on recognition from the menu bar.
2. In Safe mode, hold a closed fist to wake Mime. Quick mode accepts a finger count directly.
3. Show one through five fingers to run its assigned app.
4. In Quick mode, swipe left or right to cycle frontmost apps. Pinch your thumb and index finger to send ⌘W to the active app.

Safe mode keeps everyday movement, like typing, talking or reaching for a drink, from triggering anything. Either hand works. Motion shortcuts need Mime to be allowed under System Settings › Privacy & Security › Accessibility. ⌘W closes the active tab in a tab-aware app and the active window otherwise.

## Privacy

Everything happens on your Mac. Mime analyzes camera frames in memory with Apple's Vision framework and discards them right away. It never saves or uploads camera images or hand-tracking data, and it has no accounts, analytics or cloud services. Poses you record yourself will be stored only as a small set of numbers describing the hand's shape.

## Roadmap

- [ ] Menu-bar app
- [ ] On-device hand tracking
- [ ] Wake-then-command gesture recognition
- [ ] Actions: apps, websites, files, Shortcuts, scripts, keyboard shortcuts and media controls
- [ ] Pointer movement and left-click
- [ ] Record your own poses
- [ ] Version 0.1.0

## Requirements

- A Mac with Apple silicon
- macOS 26 or later
- A camera

## Built with

Swift, SwiftUI, AVFoundation and Apple's Vision framework, with no third-party dependencies.
