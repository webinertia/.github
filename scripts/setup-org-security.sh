#!/usr/bin/env bash
# Sets up the security policy + private vulnerability reporting across every
# repo in the webinertia GitHub org.
#
# Usage:
#   ./setup-org-security.sh <path-to-SECURITY.md> [--dry-run]
#
# What it does:
#   1. Upserts SECURITY.md into webinertia/.github (the community-health-file
#      fallback repo GitHub uses as the default SECURITY.md for any repo in
#      the org that doesn't have its own).
#   2. Enables "Private vulnerability reporting" on every existing,
#      non-archived, non-fork repo in the org.
#
# Requires: gh CLI, authenticated with 'repo' scope and admin rights on the
# webinertia org's repos.
#
# Note: hardcoded to the webinertia org on purpose — orgs are rolled out one
# at a time. To target another org (e.g. php-db), copy this script or change
# the org variable below.

set -euo pipefail

org="webinertia"
security_md="${1:?Usage: $0 <path-to-SECURITY.md> [--dry-run]}"
dry_run="${2:-}"

if [[ ! -f "$security_md" ]]; then
    echo "error: $security_md not found" >&2
    exit 1
fi

echo "== Org: $org =="

# --- Step 1: upsert SECURITY.md into <org>/.github -------------------------
health_repo="$org/.github"
echo "-> Upserting SECURITY.md into $health_repo"

if [[ "$dry_run" == "--dry-run" ]]; then
    echo "   (dry-run) would PUT contents/SECURITY.md to $health_repo"
else
    existing_sha="$(gh api "repos/$health_repo/contents/SECURITY.md" --jq .sha 2>/dev/null || true)"

    content_b64="$(base64 -w0 "$security_md")"

    if [[ -n "$existing_sha" ]]; then
        gh api -X PUT "repos/$health_repo/contents/SECURITY.md" \
            -f message="chore: update SECURITY.md" \
            -f content="$content_b64" \
            -f sha="$existing_sha" >/dev/null
        echo "   updated (was sha $existing_sha)"
    else
        gh api -X PUT "repos/$health_repo/contents/SECURITY.md" \
            -f message="chore: add SECURITY.md" \
            -f content="$content_b64" >/dev/null
        echo "   created"
    fi
fi

# --- Step 2: enable private vulnerability reporting on every repo ----------
echo "-> Enabling private vulnerability reporting on all repos in $org"

mapfile -t repos < <(gh repo list "$org" --limit 1000 --no-archived \
    --json name,isFork --jq '.[] | select(.isFork==false) | .name')

for repo in "${repos[@]}"; do
    if [[ "$dry_run" == "--dry-run" ]]; then
        echo "   (dry-run) would enable on $org/$repo"
        continue
    fi

    if gh api -X PUT "repos/$org/$repo/private-vulnerability-reporting" --silent 2>/tmp/pvr-err; then
        echo "   [ok] $org/$repo"
    else
        echo "   [skip] $org/$repo: $(cat /tmp/pvr-err)"
    fi
done

echo "== Done: $org =="
