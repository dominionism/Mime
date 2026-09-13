# Mime

**Touchless gesture control for macOS.**

Mime is a menu-bar app that watches for deliberate hand poses through your Mac's camera and turns them into actions: opening apps, websites and files, running Shortcuts and scripts, pressing keyboard shortcuts, and controlling media. The goal is a Mac you can drive with less reaching for the keyboard and mouse.

> [!NOTE]
> Mime is in early development. There's nothing to download or build yet.

## How it works

1. Turn on recognition from the menu bar.
2. Hold an open palm toward the camera to wake Mime.
3. Within a few seconds, show a command pose: fist, thumbs-up, V sign or pointing finger.
4. Mime runs the action assigned to that pose.

Waking Mime first keeps everyday movement, like typing, talking or reaching for a drink, from triggering anything. Either hand works.

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
