#!/bin/bash
# Auto-configure new external displays for niri
# Layout: 1st external = above eDP-1, 2nd = right of eDP-1, 3rd = left of eDP-1
# Use move-monitor-position.sh to change a monitor's position interactively

CONFIG_DIR="$HOME/.config/niri"
DISPLAY_CONFIG="$CONFIG_DIR/cfg/display.kdl"
KNOWN_DISPLAYS_FILE="$CONFIG_DIR/scripts/.known_displays"

# eDP-1 logical dimensions (physical / scale). Override if your laptop differs.
EDP_LOGICAL_WIDTH=1504
EDP_LOGICAL_HEIGHT=1003

# Ensure known displays file exists
mkdir -p "$CONFIG_DIR/scripts"
touch "$KNOWN_DISPLAYS_FILE"

# Function to get current connected displays
get_connected_displays() {
    niri msg -j outputs | jq -r 'keys[]'
}

# Function to check if display is already configured
is_configured() {
    local display="$1"
    grep -q "^$display$" "$KNOWN_DISPLAYS_FILE" 2>/dev/null
}

# Count already-configured external displays (excluding eDP-1) to determine layout slot
count_configured_externals() {
    grep -v "^eDP-1$" "$KNOWN_DISPLAYS_FILE" 2>/dev/null | grep -c . || echo 0
}

# Function to add display to config
# Slot: 1=above eDP-1, 2=right of eDP-1, 3=left of eDP-1, 4+=below eDP-1
configure_display() {
    local display="$1"
    local slot
    slot=$(count_configured_externals)
    slot=$((slot + 1))

    # Get display info - the JSON is keyed by display name
    local current_mode=$(niri msg -j outputs | jq -r ".[\"$display\"].current_mode")

    if [ "$current_mode" = "null" ] || [ -z "$current_mode" ]; then
        echo "Warning: Display $display has no current mode, skipping"
        return
    fi

    # Get display make and model for the comment
    local make=$(niri msg -j outputs | jq -r ".[\"$display\"].make")
    local model=$(niri msg -j outputs | jq -r ".[\"$display\"].model")
    local display_name="$make $model"
    
    # If make or model is null, just use the display port name
    if [ "$make" = "null" ] || [ "$model" = "null" ]; then
        display_name="$display"
    fi

    # Get mode details using the current_mode index
    local width=$(niri msg -j outputs | jq -r ".[\"$display\"].modes[$current_mode].width")
    local height=$(niri msg -j outputs | jq -r ".[\"$display\"].modes[$current_mode].height")
    local refresh=$(niri msg -j outputs | jq -r ".[\"$display\"].modes[$current_mode].refresh_rate")

    # Convert refresh rate from millihertz to Hz (divide by 1000)
    local refresh_rate=$(awk "BEGIN {printf \"%.3f\", $refresh / 1000}")

    # Compute position based on slot (eDP-1 at 0,0)
    local x_position y_position position_desc
    case "$slot" in
        1)
            # Above eDP-1: center horizontally, bottom touches top of eDP-1
            x_position=$(awk "BEGIN {printf \"%.0f\", ($EDP_LOGICAL_WIDTH - $width) / 2}")
            [ "$x_position" -lt 0 ] && x_position=0
            y_position=-$height
            position_desc="above eDP-1"
            ;;
        2)
            # Right of eDP-1: left edge touches right of eDP-1, center vertically
            x_position=$EDP_LOGICAL_WIDTH
            y_position=$(awk "BEGIN {printf \"%.0f\", ($EDP_LOGICAL_HEIGHT - $height) / 2}")
            [ "$y_position" -lt 0 ] && y_position=0
            position_desc="right of eDP-1"
            ;;
        3)
            # Left of eDP-1: right edge touches left of eDP-1, center vertically
            x_position=-$width
            y_position=$(awk "BEGIN {printf \"%.0f\", ($EDP_LOGICAL_HEIGHT - $height) / 2}")
            [ "$y_position" -lt 0 ] && y_position=0
            position_desc="left of eDP-1"
            ;;
        *)
            # 4+: Below eDP-1: center horizontally
            x_position=$(awk "BEGIN {printf \"%.0f\", ($EDP_LOGICAL_WIDTH - $width) / 2}")
            [ "$x_position" -lt 0 ] && x_position=0
            y_position=$EDP_LOGICAL_HEIGHT
            position_desc="below eDP-1"
            ;;
    esac

    # Add configuration to display.kdl
    printf '\n// Auto-configured: %s - %s (%s) slot=%d %s\n' "$display" "$display_name" "$(date)" "$slot" "$position_desc" >> "$DISPLAY_CONFIG"
    printf 'output "%s" {\n' "$display" >> "$DISPLAY_CONFIG"
    printf '    mode "%dx%d@%s"\n' "$width" "$height" "$refresh_rate" >> "$DISPLAY_CONFIG"
    printf '    scale 1.0\n' >> "$DISPLAY_CONFIG"
    printf '    position x=%d y=%d\n' "$x_position" "$y_position" >> "$DISPLAY_CONFIG"
    printf '}\n' >> "$DISPLAY_CONFIG"

    # Mark as known
    echo "$display" >> "$KNOWN_DISPLAYS_FILE"

    # Reload niri config
    niri msg action load-config-file

    echo "✓ Configured new display: $display ($display_name) at position ($x_position, $y_position) - $position_desc"
    echo "  Resolution: ${width}x${height}@${refresh_rate}"

    if command -v notify-send &> /dev/null; then
        notify-send "New Display Configured" \
            "$display_name - $position_desc\nPosition: ($x_position, $y_position)\nResolution: ${width}x${height}@${refresh_rate}"
    fi
}

# Main monitoring loop
main() {
    echo "Starting display monitor..."
    echo "Monitoring for new external displays..."

    while true; do
        for display in $(get_connected_displays); do
            # Skip internal display
            if [[ "$display" == "eDP-1" ]]; then
                continue
            fi

            # If not configured, configure it
            if ! is_configured "$display"; then
                echo "New display detected: $display"
                configure_display "$display"
            fi
        done

        # Check every 2 seconds
        sleep 2
    done
}

# Parse command line arguments
case "$1" in
    --once)
        # Run once to configure any new displays
        for display in $(get_connected_displays); do
            if [[ "$display" != "eDP-1" ]] && ! is_configured "$display"; then
                configure_display "$display"
            fi
        done
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Auto-configure external displays for niri"
        echo "Layout: 1st=above eDP-1, 2nd=right, 3rd=left, 4+=below"
        echo ""
        echo "Options:"
        echo "  (no args)    Run in monitoring mode (continuous)"
        echo "  --once       Configure any new displays once and exit"
        echo "  --help, -h   Show this help message"
        echo ""
        echo "Reposition monitors: $CONFIG_DIR/scripts/move-monitor-position.sh"
        ;;
    *)
        # Default: run in monitoring mode
        main
        ;;
esac
