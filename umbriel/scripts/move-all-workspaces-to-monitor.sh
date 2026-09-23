#!/bin/bash
# Move all occupied workspaces onto a neighboring monitor.
# Usage: move-all-workspaces-to-monitor.sh [DIRECTION]
#   no args:   Interactive — select left / right / up / down
#   1 arg:     left|right|up|down   Move all workspaces that way
#
# Umbriel keeps an independent workspace list on each output. Named
# workspaces such as "1".."7" therefore exist on every monitor. This
# script moves each source workspace's windows onto the matching name
# (or index) on the target output, instead of relocating workspace
# objects the way niri does.

set -u

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Required command not found: $1" >&2
        exit 1
    }
}

need_cmd umbriel
need_cmd jq

workspaces_json() {
    umbriel workspaces --json 2>/dev/null
}

outputs_json() {
    umbriel outputs --json 2>/dev/null
}

windows_json() {
    umbriel windows --json 2>/dev/null
}

msg() {
    umbriel msg "$1" >/dev/null 2>&1
}

get_focused_output() {
    workspaces_json | jq -r '.[] | select(.focused == true) | .output' | head -1
}

get_focused_workspace() {
    workspaces_json | jq -c '.[] | select(.focused == true)' | head -1
}

get_display_label() {
    local display="$1"
    local make model
    make=$(outputs_json | jq -r --arg o "$display" '.[] | select(.name == $o) | .make // empty')
    model=$(outputs_json | jq -r --arg o "$display" '.[] | select(.name == $o) | .model // empty')
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

# Switch to the active workspace on $output so later directional
# output actions start from that monitor.
focus_output() {
    local output="$1"
    local idx
    idx=$(workspaces_json | jq -r --arg o "$output" '
        [.[] | select(.output == $o)] |
        (map(select(.active == true)) | .[0].index) // (min_by(.index).index)
    ')
    [ -n "$idx" ] && [ "$idx" != "null" ] || return 1
    msg "workspace-switch:${idx}/${output}"
}

# Umbriel requires quoted selectors for all-digit names ("1", "2", …).
workspace_selector() {
    local ws_json="$1"
    local output="$2"
    jq -r --arg o "$output" '
        if .named == true then
            "\"\(.name)\"/" + $o
        else
            "\(.index)/" + $o
        end
    ' <<<"$ws_json"
}

# Neighbor of $from in $dir, using Umbriel's output-focus-* logic.
# Restores focus to $from. Prints nothing if there is no neighbor.
peek_neighbor() {
    local from="$1"
    local dir="$2"
    focus_output "$from"
    sleep 0.05
    msg "output-focus-${dir}"
    local there
    there=$(get_focused_output)
    focus_output "$from"
    sleep 0.05
    if [ -n "$there" ] && [ "$there" != "$from" ]; then
        echo "$there"
    fi
}

# Primary (and optional secondary) direction from one output's center
# to another's, in logical compositor coordinates.
geometry_directions() {
    outputs_json | jq -r --arg from "$1" --arg to "$2" '
        def logical_size(o):
            (o.modes[] | select(.current == true)) as $m |
            [($m.width / o.scale), ($m.height / o.scale)];
        def center(o):
            logical_size(o) as $s |
            [o.position.x + $s[0] / 2, o.position.y + $s[1] / 2];
        ([.[] | select(.name == $from)][0]) as $a |
        ([.[] | select(.name == $to)][0]) as $b |
        if $a == null or $b == null then empty else
            (center($a) + center($b)) as $c |
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
        end
    '
}

interactive_select_direction() {
    local here
    here=$(get_focused_output)
    if [ -z "$here" ]; then
        echo "No focused monitor" >&2
        exit 1
    fi

    local opts=()
    local -A dir_taken=()
    local o primary
    for o in $(outputs_json | jq -r '.[] | select(.enabled == true) | .name'); do
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

move_windows_to_workspace() {
    local src_id="$1"
    local dest_sel="$2"
    local ids count=0 id
    ids=$(windows_json | jq -r --arg id "$src_id" '
        [.[]
         | select(.workspace == $id)
         | select(.scratchpad == "")
         | select(.title != "move-all-workspaces-to-monitor")]
        | sort_by(.x, .y)
        | .[].id
    ')
    [ -z "$ids" ] && echo 0 && return 0
    for id in $ids; do
        msg "window-focus:${id}"
        sleep 0.05
        msg "window-move-to-workspace:${dest_sel}"
        count=$((count + 1))
        sleep 0.05
    done
    echo "$count"
}

move_all_in_direction() {
    local dir="$1"
    local origin target focused_ws
    origin=$(get_focused_output)
    if [ -z "$origin" ]; then
        echo "No focused monitor" >&2
        exit 1
    fi

    focused_ws=$(get_focused_workspace)
    target=$(peek_neighbor "$origin" "$dir")
    if [ -z "$target" ]; then
        echo "No monitor $dir of $(get_display_label "$origin") [$origin]" >&2
        exit 1
    fi

    local count=0
    local sources source
    sources=$(workspaces_json | jq -r --arg t "$target" '
        [.[] | select(.output != $t and .occupied == true) | .output]
        | unique | .[]
    ')

    for source in $sources; do
        local ws dest_sel moved
        while IFS= read -r ws; do
            [ -z "$ws" ] && continue
            dest_sel=$(workspace_selector "$ws" "$target")
            moved=$(move_windows_to_workspace "$(jq -r '.id' <<<"$ws")" "$dest_sel")
            count=$((count + moved))
        done < <(workspaces_json | jq -c --arg s "$source" '
            [.[] | select(.output == $s and .occupied == true)] | sort_by(.index) | .[]
        ')
    done

    if [ -n "$focused_ws" ] && [ "$focused_ws" != "null" ]; then
        msg "workspace-switch:$(workspace_selector "$focused_ws" "$target")"
    else
        focus_output "$target"
    fi

    echo "✓ Moved $count window(s) $dir to $(get_display_label "$target") [$target] (workspace names preserved)"
}

case "${1:-}" in
    "")
        dir=$(interactive_select_direction)
        [ -n "$dir" ] && move_all_in_direction "$dir"
        ;;
    --help|-h)
        echo "Usage: $0 [DIRECTION]"
        echo ""
        echo "Move all occupied workspaces to a neighboring monitor."
        echo "Windows land on the matching named/index workspace on the target."
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
