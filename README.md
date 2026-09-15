# Mime

**Touchless gesture control for macOS.**

Mime is a menu-bar app that watches for deliberate hand poses through your Mac's camera and turns them into actions: opening apps, websites and files, running Shortcuts and scripts, pressing keyboard shortcuts, and controlling media. The goal is a Mac you can drive with less reaching for the keyboard and mouse.

> [!NOTE]
> Mime is in early development. There's nothing to download or build yet.

## How it works

1. Turn on recognition from the menu bar.
2. In Safe mode, hold a closed fist to wake Mime. Quick mode accepts a finger count directly.
3. Show one through five fingers to run its assigned app. Any combination counts, including your thumb. In Quick mode, change counts directly, or lower your hand briefly to repeat the same count.
4. Swipe left or right to cycle through open apps in a stable order, pausing briefly between swipes. Quick mode runs swipes directly; Safe mode requires the fist wake first.

Safe mode requires a deliberate wake and hold to reduce accidental activations during everyday movement. Either hand works. App launching and switching use macOS app activation and do not require Accessibility permission.

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
