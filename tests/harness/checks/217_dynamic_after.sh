#!/usr/bin/env bash
# harness: outputs=2
# A fixed prefix keeps its names and identities while its numbered dynamic tail grows and survives output recreation.
set -euo pipefail

readonly WORKSPACE="${UMBRIEL_WORKSPACE_CLIENT:-./build-debug/tests/workspace-client}"

workspace_names() {
  "$UMBRIEL" workspaces --json | jq -r '[.[] | select(.output == "HEADLESS-1")] | sort_by(.index) | map(.name) | join(" ")'
}

workspace_id() {
  "$WORKSPACE" --all | awk -F'\t' -v name="$1" '$1 ~ /^HEADLESS-1:/ && $2 == name { print $1; exit }'
}

active_workspace() {
  "$WORKSPACE" --active | awk -F'\t' '$1 ~ /^HEADLESS-1:/ { print $2 }'
}

window_home() {
  local id name
  id=$("$UMBRIEL" windows --json | jq -r --arg title "$1" '.[] | select(.title == $title) | .workspace')
  name=$("$WORKSPACE" --all | awk -F'\t' -v id="$id" '$1 == id { print $2 }')
  [[ -n $id && -n $name ]] && printf '%s/%s' "${id%%:*}" "$name"
  return 0
}

wait_for() {
  local description=$1 expected=$2 actual=
  shift 2
  for _ in $(seq 50); do
    actual=$("$@")
    [[ $actual == "$expected" ]] && return 0
    sleep 0.1
  done
  echo "expected $description '$expected', got '$actual'"
  return 1
}

printf '\n[output.HEADLESS-1]\nworkspaces = ["WEB", "CHAT"]\ndynamic_after = true\n' >> "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
wait_for "workspace names" "WEB CHAT 3" workspace_names

"$UMBRIEL" msg workspace-switch:1/HEADLESS-1 > /dev/null
wait_for "numeric prefix selection" "WEB" active_workspace
web_id=$(workspace_id WEB)
chat_id=$(workspace_id CHAT)

foot --title=hybrid-fixed sh -c 'sleep 120' > /dev/null 2>&1 &
wait_for "fixed window home" "HEADLESS-1/WEB" window_home hybrid-fixed
"$UMBRIEL" msg workspace-switch:3/HEADLESS-1 > /dev/null
foot --title=hybrid-tail sh -c 'sleep 120' > /dev/null 2>&1 &
wait_for "workspace names" "WEB CHAT 3 4" workspace_names
wait_for "dynamic window home" "HEADLESS-1/3" window_home hybrid-tail
tail_id=$(workspace_id 3)

sed 's/workspaces = \["WEB", "CHAT"\]/workspaces = ["CHAT", "WEB"]/' "$UMBRIEL_CONFIG" > "$UMBRIEL_CONFIG.next"
mv "$UMBRIEL_CONFIG.next" "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
[[ $(workspace_id WEB) == "$web_id" && $(workspace_id CHAT) == "$chat_id" && $(workspace_id 3) == "$tail_id" ]] || {
  echo "workspace identities changed across a prefix reorder"
  exit 1
}

"$UMBRIEL" msg workspace-switch:1/HEADLESS-1 > /dev/null
wait_for "reordered first workspace" "CHAT" active_workspace
"$UMBRIEL" msg workspace-switch:2/HEADLESS-1 > /dev/null
wait_for "reordered second workspace" "WEB" active_workspace

"$UMBRIEL" msg workspace-move-up > /dev/null
"$UMBRIEL" msg workspace-switch:1/HEADLESS-1 > /dev/null
wait_for "first workspace after a blocked prefix move" "CHAT" active_workspace
"$UMBRIEL" msg workspace-switch:WEB/HEADLESS-1 > /dev/null

"$UMBRIEL" output-destroy HEADLESS-1 > /dev/null
"$UMBRIEL" output-create HEADLESS-1 > /dev/null
wait_for "fixed window home" "HEADLESS-1/WEB" window_home hybrid-fixed
wait_for "dynamic window home" "HEADLESS-1/3" window_home hybrid-tail
wait_for "restored active workspace" "WEB" active_workspace

echo "the fixed prefix and dynamic tail kept their lifecycle boundaries across reload and output recreation"
