#!/bin/bash
# Move all workspaces to a neighboring monitor (preserves order)
# Usage: move-all-workspaces-to-monitor.sh [DIRECTION]
#   no args:   Interactive — select left / right / up / down
#   1 arg:     left|right|up|down   Move all workspaces that way

# Get currently focused output name
get_focused_output() {
    niri msg -j focused-output 2>/dev/null | jq -r '.name // empty'
}

# Output that currently has the focused workspace
get_focused_workspace_output() {
    niri msg -j workspaces 2>/dev/null | jq -r '.[] | select(.is_focused == true) | .output' | head -1
}

# Human-readable label (make + model, or output name)
get_display_label() {
    local display="$1"
    local make model
    make=$(niri msg -j outputs 2>/dev/null | jq -r --arg o "$display" '.[$o].make // empty')
    model=$(niri msg -j outputs 2>/dev/null | jq -r --arg o "$display" '.[$o].model // empty')
    if [ -n "$make" ] && [ -n "$model" ]; then
        echo "$make $model"
    else
        echo "$display"
    fi
}

normalize_dir() {
    local a="${1,,}"
    a="${a#--}"
    case "$a" in
        left|l)  echo left ;;
        right|r) echo right ;;
        up|u)    echo up ;;
        down|d)  echo down ;;
        *)       return 1 ;;
    esac
}

# Neighbor of $from in $dir, using niri's own focus-monitor-* logic.
# Restores focus to $from. Prints nothing if there is no neighbor.
peek_neighbor() {
    local from="$1"
    local dir="$2"
    niri msg action focus-monitor "$from"
    sleep 0.05
    niri msg action "focus-monitor-$dir"
    local there
    there=$(get_focused_output)
    if [ -n "$there" ] && [ "$there" != "$from" ]; then
        niri msg action focus-monitor "$from"
        sleep 0.05
        echo "$there"
    else
        niri msg action focus-monitor "$from"
        sleep 0.05
    fi
}

# Primary (and optional secondary) direction from one output's center to another's.
# Used so move-workspace-to-monitor-* can hop toward the target from any source.
geometry_directions() {
    niri msg -j outputs 2>/dev/null | jq -r --arg from "$1" --arg to "$2" '
        def center(o): [o.logical.x + o.logical.width / 2, o.logical.y + o.logical.height / 2];
        (center(.[$from]) + center(.[$to])) as $c |
        ($c[2] - $c[0]) as $dx | ($c[3] - $c[1]) as $dy |
        (if $dx < 0 then -$dx else $dx end) as $adx |
        (if $dy < 0 then -$dy else $dy end) as $ady |
        (if $dx < 0 then "left" else "right" end) as $horiz |
        (if $dy < 0 then "up" else "down" end) as $vert |
        if $adx >= $ady then
            $horiz + " " + $vert
        else
            $vert + " " + $horiz
        end
    '
}

# Move the currently focused workspace onto $target via directional actions.
move_focused_workspace_to_target() {
    local target="$1"
    local hops=0
    while [ "$hops" -lt 8 ]; do
        local cur
        cur=$(get_focused_workspace_output)
        [ "$cur" = "$target" ] && return 0
        [ -z "$cur" ] && return 1

        local primary secondary
        read -r primary secondary <<< "$(geometry_directions "$cur" "$target")"
        [ -z "$primary" ] && return 1

        niri msg action "move-workspace-to-monitor-$primary"
        sleep 0.05
        local now
        now=$(get_focused_workspace_output)
        if [ "$now" = "$cur" ] && [ -n "$secondary" ]; then
            niri msg action "move-workspace-to-monitor-$secondary"
            sleep 0.05
            now=$(get_focused_workspace_output)
        fi
        if [ "$now" = "$cur" ]; then
            echo "Cannot move workspace from $cur toward $target" >&2
            return 1
        fi
        hops=$((hops + 1))
    done
    return 1
}

interactive_select_direction() {
    local here
    here=$(get_focused_output)
    if [ -z "$here" ]; then
        echo "No focused monitor" >&2
        exit 1
    fi

    # List each direction whose primary neighbor (by layout geometry) exists.
    # Actual target is still resolved with niri's focus-monitor-* after selection.
    local opts=()
    local -A dir_taken=()
    local o primary
    for o in $(niri msg -j outputs 2>/dev/null | jq -r 'keys[]'); do
        [ "$o" = "$here" ] && continue
        primary=$(geometry_directions "$here" "$o" | awk '{print $1}')
        [ -z "$primary" ] && continue
        [ -n "${dir_taken[$primary]:-}" ] && continue
        dir_taken[$primary]=1
        opts+=("$primary  →  $(get_display_label "$o") [$o]")
    done

    if [ ${#opts[@]} -eq 0 ]; then
        echo "No neighboring monitors from $(get_display_label "$here") [$here]" >&2
        exit 1
    fi

    local sel
    if command -v fzf &>/dev/null; then
        sel=$(printf '%s\n' "${opts[@]}" | fzf --prompt="Move ALL workspaces: ")
    else
        echo "Move ALL workspaces to the monitor:"
        select sel in "${opts[@]}"; do
            [ -n "$sel" ] && break
        done
    fi
    [ -z "$sel" ] && exit 1

    echo "${sel%% *}"
}

# Move all workspaces to the monitor in $dir of the currently focused one.
# Preserves order (by source output, then idx).
# - Park on the target's last (empty) workspace so we never move the focused one by accident
# - For each source: repeatedly move workspace at idx 1. After each move, the next
#   becomes idx 1. The last workspace on each monitor is always empty (niri), so we stop before it.
move_all_in_direction() {
    local dir="$1"
    local origin target
    origin=$(get_focused_output)
    if [ -z "$origin" ]; then
        echo "No focused monitor" >&2
        exit 1
    fi

    target=$(peek_neighbor "$origin" "$dir")
    if [ -z "$target" ]; then
        echo "No monitor $dir of $(get_display_label "$origin") [$origin]" >&2
        exit 1
    fi

    local count=0
    local active_id
    active_id=$(niri msg -j workspaces 2>/dev/null | jq -r '.[] | select(.is_active == true) | .id' | head -1)

    niri msg action focus-monitor "$target"
    sleep 0.1
    local last_idx
    last_idx=$(niri msg -j workspaces 2>/dev/null | jq -r --arg t "$target" '[.[] | select(.output == $t) | .idx] | max')
    if [ -n "$last_idx" ] && [ "$last_idx" != "null" ]; then
        niri msg action focus-workspace "$last_idx"
        sleep 0.1
    fi

    local sources
    sources=$(niri msg -j workspaces 2>/dev/null | jq -r --arg t "$target" '
        [.[] | select(.output != $t) | .output] | unique | sort | .[]
    ')

    local source
    for source in $sources; do
        local n to_move
        n=$(niri msg -j workspaces 2>/dev/null | jq -r --arg s "$source" '[.[] | select(.output == $s)] | length')
        to_move=$((n - 1))
        local desired_order
        desired_order=$(niri msg -j workspaces 2>/dev/null | jq -r --arg s "$source" '
            [.[] | select(.output == $s)] | sort_by(.idx) | (.[:-1] | .[].id)
        ')
        local i
        for i in $(seq 1 "$to_move"); do
            niri msg action focus-monitor "$source"
            sleep 0.15
            niri msg action focus-workspace 1
            sleep 0.08
            move_focused_workspace_to_target "$target" || true
            count=$((count + 1))
            sleep 0.05
        done
        if [ -n "$active_id" ] && [ "$active_id" != "null" ]; then
            local desired_idx actual_idx
            desired_idx=$(echo "$desired_order" | grep -n "^${active_id}$" | cut -d: -f1)
            actual_idx=$(niri msg -j workspaces 2>/dev/null | jq -r --arg t "$target" --argjson wid "$active_id" '
                [.[] | select(.output == $t)] | sort_by(.idx) |
                to_entries[] | select(.value.id == $wid) | (.key + 1)
            ')
            if [ -n "$desired_idx" ] && [ -n "$actual_idx" ] && [ "$desired_idx" != "$actual_idx" ]; then
                local moves=$((desired_idx - actual_idx))
                niri msg action focus-monitor "$target"
                sleep 0.08
                niri msg action focus-workspace "$actual_idx"
                sleep 0.05
                local j
                if [ "$moves" -gt 0 ]; then
                    for j in $(seq 1 "$moves"); do
                        niri msg action move-workspace-down
                        sleep 0.05
                    done
                else
                    for j in $(seq 1 "$((-moves))"); do
                        niri msg action move-workspace-up
                        sleep 0.05
                    done
                fi
            fi
        fi
    done

    [ $count -gt 0 ] && niri msg action focus-monitor "$target"

    echo "✓ Moved $count workspace(s) $dir to $(get_display_label "$target") [$target] (order preserved)"
}

case "${1:-}" in
    "")
        dir=$(interactive_select_direction)
        [ -n "$dir" ] && move_all_in_direction "$dir"
        ;;
    --help|-h)
        echo "Usage: $0 [DIRECTION]"
        echo ""
        echo "Move all workspaces to a neighboring monitor (preserves order)."
        echo "Direction is relative to the currently focused monitor."
        echo ""
        echo "  (no args)   Interactive: select left / right / up / down"
        echo "  1 arg       left|right|up|down"
        echo ""
        echo "Examples:"
        echo "  $0           # Interactive: pick a direction"
        echo "  $0 left      # Move all workspaces to the monitor on the left"
        echo "  $0 up        # Move all workspaces to the monitor above"
        ;;
    *)
        dir=$(normalize_dir "$1") || {
            echo "Unknown direction: $1 (use left, right, up, or down)" >&2
            exit 1
        }
        move_all_in_direction "$dir"
        ;;
esac
