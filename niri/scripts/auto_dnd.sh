#!/bin/bash

DND_ACTIVE=false

while true; do
    # Check if Niri is actively outputting a video stream (screencast)
    if pw-link -l | grep -q "niri:output_"; then
        if [ "$DND_ACTIVE" = false ]; then
            qs -c noctalia-shell ipc call notifications enableDND
            DND_ACTIVE=true
        fi
    else
        if [ "$DND_ACTIVE" = true ]; then
            qs -c noctalia-shell ipc call notifications disableDND
            DND_ACTIVE=false
        fi
    fi

    sleep 2
done
