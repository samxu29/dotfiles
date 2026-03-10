#!/bin/bash

# Check if any AC adapter or dock is reporting as 'online' (plugged in)
if grep -q "1" /sys/class/power_supply/*/online 2>/dev/null; then
    # We are plugged in or docked. Just suspend to RAM.
    systemctl suspend
else
    # We are on battery. Use the hybrid sleep-then-hibernate mode.
    systemctl suspend-then-hibernate
fi
