#!/usr/bin/env bash
set -euo pipefail

LINK_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMP_WRAPPER_PY="$SCRIPT_DIR/multica_omp_wrapper.py"

mkdir -p "$LINK_DIR"
chmod +x "$OMP_WRAPPER_PY"

link_wrapper() {
  local runtime_name="$1"
  local link_path="$LINK_DIR/$runtime_name"

  ln -sfn "$OMP_WRAPPER_PY" "$link_path"
  printf '%s\n' "$link_path"
}

upsert_profile() {
  local display_name="$1"
  local command_name="$2"
  local profile_id

  profile_id="$(multica runtime profile list --output json \
    | jq -r --arg name "$display_name" '.[] | select(.display_name == $name) | .id' \
    | head -n 1)"

  if [ "$profile_id" = "null" ]; then
    profile_id=""
  fi

  if [ -z "$profile_id" ]; then
    profile_id="$(multica runtime profile create \
      --display-name "$display_name" \
      --protocol-family pi \
      --command-name "$command_name" \
      --output json \
      | jq -r '.id')"
  else
    multica runtime profile update "$profile_id" \
      --display-name "$display_name" \
      --command-name "$command_name" \
      --output json >/dev/null
  fi

  printf '%s\n' "$profile_id"
}

SMOL_LINK_PATH="$(link_wrapper "multica-omp-smol")"
REASONING_LINK_PATH="$(link_wrapper "multica-omp-reasoning")"
CODING_LINK_PATH="$(link_wrapper "multica-omp-coding")"

SMOL_ID="$(upsert_profile "OMP Smol" "multica-omp-smol")"
REASONING_ID="$(upsert_profile "OMP Reasoning" "multica-omp-reasoning")"
CODING_ID="$(upsert_profile "OMP Coding" "multica-omp-coding")"

multica runtime profile set-path "$SMOL_ID" --path "$SMOL_LINK_PATH"
multica runtime profile set-path "$REASONING_ID" --path "$REASONING_LINK_PATH"
multica runtime profile set-path "$CODING_ID" --path "$CODING_LINK_PATH"

echo "Configured OMP runtime profiles: OMP Smol, OMP Reasoning, OMP Coding"