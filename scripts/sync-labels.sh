#!/usr/bin/env bash
# Syncs the org-wide canonical label set into every repo in the webinertia org.
#
# Usage:
#   ./sync-labels.sh <path-to-labels.yml> [--dry-run]
#
# What it does, for every non-archived, non-fork repo in the org:
#   1. Creates/updates every label defined in labels.yml (name, colour and
#      description). Idempotent — running it twice changes nothing.
#   2. Repairs casing drift by renaming an existing label in place, so its
#      issue associations survive.
#   3. Re-labels open items off every retired label named in `renames` below,
#      then deletes every label that labels.yml does not define.
#
# Requires: gh CLI, python3 with PyYAML, and a token with admin rights on every
# repo in the org. In CI that is the org-wide App token; locally a personal
# token with `repo` scope is enough.
#
# Note: hardcoded to the webinertia org on purpose — orgs are rolled out one
# at a time. To target another org, copy this script or change `org` below.

set -euo pipefail

org="webinertia"
labels_yml="${1:?Usage: $0 <path-to-labels.yml> [--dry-run]}"
dry_run="${2:-}"

if [[ ! -f "$labels_yml" ]]; then
    echo "error: $labels_yml not found" >&2
    exit 1
fi

# Retired labels whose meaning must survive deletion: open items still carrying
# the old label are re-labelled before it is removed. Closed items keep no
# association — they are history, and re-labelling them only adds timeline
# noise. Format: "<old label>|<canonical label>"
renames=(
    "Urgent|priority: Critical"
    "New Feature|enhancement"
    "BugFix|bug"
    "BC Breakage|breaking change"
    "CI/CD/SA|tooling-alignment"
    "HouseKeeping|enhancement"
)

run() {
    if [[ "$dry_run" == "--dry-run" ]]; then
        # %q so the printed command is faithful — descriptions contain spaces,
        # apostrophes and semicolons.
        printf '   (dry-run)'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

relabel_open_items() {
    local slug="$1" old="$2" new="$3" number
    local -a numbers=()

    while IFS= read -r number; do
        if [[ -n "$number" ]]; then
            numbers+=("$number")
        fi
    done < <(gh api -X GET search/issues \
        -f q="repo:$slug label:\"$old\" is:open" -f per_page=100 \
        --jq '.items[].number')

    for number in "${numbers[@]}"; do
        echo "   re-labelling #$number: $old -> $new"
        run gh api -X POST "repos/$slug/issues/$number/labels" -f "labels[]=$new"
    done
}

# --- Read the canonical labels straight out of labels.yml ------------------
if ! python3 -c 'import yaml' 2>/dev/null; then
    echo "-> PyYAML missing, installing it"
    python3 -m pip install --quiet --disable-pip-version-check pyyaml ||
        python3 -m pip install --quiet --disable-pip-version-check --break-system-packages pyyaml
fi

labels_tsv="$(
    python3 - "$labels_yml" <<'PY'
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    entries = yaml.safe_load(handle)

for entry in entries:
    description = entry.get("description") or ""
    print(f"{entry['name']}\t{entry['color']}\t{description}")
PY
)"

echo "== Org: $org =="
echo "-> Canonical labels: $(grep -c . <<< "$labels_tsv")"

# --- Fan out across the org -----------------------------------------------
mapfile -t repos < <(
    gh repo list "$org" --limit 400 --json name,isArchived,isFork \
        --jq '.[] | select(.isArchived == false and .isFork == false) | .name' | sort
)

for repo in "${repos[@]}"; do
    slug="$org/$repo"
    echo "-> $slug"

    mapfile -t existing < <(gh label list -R "$slug" --limit 200 --json name --jq '.[].name')

    declare -A existing_by_key=()
    declare -A canonical_by_key=()
    for name in "${existing[@]}"; do
        existing_by_key["${name,,}"]="$name"
    done

    while IFS=$'\t' read -r name color description; do
        if [[ -z "$name" ]]; then
            continue
        fi
        canonical_by_key["${name,,}"]="$name"
        current="${existing_by_key["${name,,}"]:-}"
        if [[ -z "$current" ]]; then
            run gh label create "$name" -R "$slug" --color "$color" --description "$description"
        elif [[ "$current" != "$name" ]]; then
            run gh label edit "$current" -R "$slug" --name "$name" --color "$color" --description "$description"
        else
            run gh label create "$name" -R "$slug" --color "$color" --description "$description" --force
        fi
    done <<< "$labels_tsv"

    for name in "${existing[@]}"; do
        if [[ -n "${canonical_by_key["${name,,}"]:-}" ]]; then
            continue
        fi

        replacement=""
        for pair in "${renames[@]}"; do
            if [[ "${pair%%|*}" == "$name" ]]; then
                replacement="${pair##*|}"
            fi
        done
        if [[ -n "$replacement" ]]; then
            relabel_open_items "$slug" "$name" "$replacement"
        fi

        run gh label delete "$name" -R "$slug" --yes
    done
done

echo "== Done =="
