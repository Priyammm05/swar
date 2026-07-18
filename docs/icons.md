# Icon system

Swar uses the two supplied SVGs for different platform roles.

## Green app icon

Source: `apps/logo/svar_logo_large_green_centered.svg`

This is the full-color application identity. It appears in the macOS Dock, Finder, the Windows taskbar, File Explorer, and the application executable.

The SVG is an opaque square. Its background uses a radial green gradient with `#6B8F80`, `#537C6A`, `#3F6858`, and `#2F5547`. The waveform mark uses `#080A09`.

## macOS menu bar icon

Source: `apps/logo/svar_logo_mark_black_centered.svg`

This source is a transparent black mark, not a white image. Swar loads it as an AppKit template image. macOS then chooses the visible color for the current menu bar appearance. It can render dark on a light menu bar and white on a dark menu bar.

Do not replace it with a hardcoded white image. A white-only icon can disappear against a light menu bar.

Closing the Swar window leaves the menu bar item running. Its menu can reopen Swar or quit the app.

## Windows notification area

Windows has a notification area, also called the system tray, at the right side of the taskbar. It is the closest equivalent to the macOS menu bar, but Windows does not provide the same dependable template-image recoloring.

The initial Windows build uses the green icon for the executable and taskbar. If Swar adds a persistent tray workflow, it should ship separate light and dark monochrome tray assets and select the correct one when the Windows theme changes.

## Regenerating native assets

Install `rsvg-convert` and `ffmpeg`, then run:

```sh
./scripts/generate_icons.sh
```

The script generates the complete macOS app icon set, the macOS menu bar image set, and a seven-size Windows `.ico` file from the source SVGs.
