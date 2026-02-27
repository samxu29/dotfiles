#!/bin/bash

# Device paths from your libinput list:
# Keyboard: /dev/input/event2
# Touchpad: /dev/input/event8

# We use stdbuf to ensure the grep doesn't lag
stdbuf -oL libinput debug-events --device /dev/input/event2 --device /dev/input/event8 | while read -r line; do
    # Check if a key was pressed or touchpad was touched
    if echo "$line" | grep -qE "KEYBOARD_KEY|POINTER_MOTION|TOUCH_DOWN"; then
        # Check if the screen is currently off to avoid spamming the command
        if niri msg outputs | grep -A 10 "eDP-1" | grep -q "Disabled"; then
            niri msg output eDP-1 on
        fi
    fi
done
