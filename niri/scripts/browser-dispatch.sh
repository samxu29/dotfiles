#!/bin/bash

# 1. Get the list of windows
# 2. Sort by focus_timestamp.secs and focus_timestamp.nanos descending
# 3. Filter for app_ids containing 'chrome' or 'firefox'
# 4. Take the top result

LAST_BROWSER=$(niri msg --json windows | jq -r '
  sort_by(.focus_timestamp.secs, .focus_timestamp.nanos) | reverse | 
  .[] | select(.app_id | test("firefox|chrome|google-chrome"; "i")) | 
  .app_id' | head -n 1)

case "$LAST_BROWSER" in
    *chrome*)
        google-chrome-stable "$1"
        ;;
    *firefox*)
        firefox "$1"
        ;;
    *)
        # If no browser history found, default to Firefox
        firefox "$1"
        ;;
esac
