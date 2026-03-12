#!/usr/bin/env python3
"""
iTerm2 AutoLaunch script: Paste clipboard images as file paths.

When Cmd+Shift+V is pressed:
- If the clipboard contains an image, save it to /tmp and type the file path
- If no image, fall back to normal text paste

Installed by: crab setup
"""

import iterm2
import time

from AppKit import NSPasteboard, NSPasteboardTypePNG, NSPasteboardTypeTIFF
from AppKit import NSPasteboardTypeString, NSBitmapImageRep, NSPNGFileType


def save_clipboard_image(filepath):
    """Save clipboard image to filepath using PyObjC. Returns True on success."""
    pb = NSPasteboard.generalPasteboard()

    # Try PNG first
    png_data = pb.dataForType_(NSPasteboardTypePNG)
    if png_data is not None:
        with open(filepath, "wb") as f:
            f.write(png_data.bytes())
        return True

    # Fall back to TIFF and convert to PNG
    tiff_data = pb.dataForType_(NSPasteboardTypeTIFF)
    if tiff_data is not None:
        rep = NSBitmapImageRep.imageRepWithData_(tiff_data)
        if rep is not None:
            png_data = rep.representationUsingType_properties_(NSPNGFileType, {})
            if png_data is not None:
                with open(filepath, "wb") as f:
                    f.write(png_data.bytes())
                return True

    return False


def get_clipboard_text():
    """Get text from clipboard using PyObjC."""
    pb = NSPasteboard.generalPasteboard()
    return pb.stringForType_(NSPasteboardTypeString) or ""


async def main(connection):
    app = await iterm2.async_get_app(connection)

    # Shift changes characters_ignoring_modifiers to uppercase
    pattern_lower = iterm2.KeystrokePattern()
    pattern_lower.characters_ignoring_modifiers = "v"
    pattern_lower.required_modifiers = [iterm2.Modifier.COMMAND, iterm2.Modifier.SHIFT]
    pattern_lower.forbidden_modifiers = [iterm2.Modifier.OPTION, iterm2.Modifier.CONTROL]

    pattern_upper = iterm2.KeystrokePattern()
    pattern_upper.characters_ignoring_modifiers = "V"
    pattern_upper.required_modifiers = [iterm2.Modifier.COMMAND, iterm2.Modifier.SHIFT]
    pattern_upper.forbidden_modifiers = [iterm2.Modifier.OPTION, iterm2.Modifier.CONTROL]

    async with iterm2.KeystrokeMonitor(connection) as monitor:
        async with iterm2.KeystrokeFilter(connection, [pattern_lower, pattern_upper]):
            while True:
                keystroke = await monitor.async_get()

                # Only handle Cmd+Shift+V
                mods = keystroke.modifiers
                if (keystroke.characters_ignoring_modifiers.lower() != "v" or
                        iterm2.Modifier.COMMAND not in mods or
                        iterm2.Modifier.SHIFT not in mods):
                    continue

                try:
                    window = app.current_terminal_window
                    if window is None:
                        continue
                    session = window.current_tab.current_session

                    # Try to save clipboard image
                    timestamp = int(time.time() * 1000)
                    filepath = f"/tmp/clipboard_{timestamp}.png"

                    if save_clipboard_image(filepath):
                        await session.async_send_text(filepath)
                    else:
                        # No image in clipboard, fall back to normal text paste
                        text = get_clipboard_text()
                        if text:
                            await session.async_send_text(text)
                except Exception:
                    pass


iterm2.run_forever(main)
