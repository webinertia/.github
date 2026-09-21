# Label Sync — running this in another organisation

Keeps every repository in an org's labels identical to one canonical list, using a
GitHub App as the credential and a script in the org's `.github` repo as the engine.

This document is the setup guide for adopting the pattern in a **different** org. It
assumes you are copying the files, not borrowing webinertia's app — see
[Why you need your own app](#why-you-need-your-own-app).

---

## Files to copy into your org's `.github` repo

Everything lives in this repo. Copy these three files, keeping the **exact paths** — the
workflow's `paths:` trigger and its `run:` step both reference them:

| Source in `webinertia/.github`      | Destination in your `.github` repo  | Required | Change on arrival |
| ----------------------------------- | ----------------------------------- | -------- | ----------------- |
| `.github/labels.yml`                | `.github/labels.yml`                | Yes      | Replace with your own canonical label set |
| `.github/workflows/label-sync.yml`  | `.github/workflows/label-sync.yml`  | Yes      | `branches: [master]` → your default branch |
| `scripts/sync-labels.sh`            | `scripts/sync-labels.sh`            | Yes      | `org="webinertia"` → your org slug; clear the `renames` array |

Optional — only if you want the surrounding org config too. These files *assume* the
labels exist, so copy them after `labels.yml` is settled:

| Source | Notes |
| ------ | ----- |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Requires the `status: Not Confirmed` label |
| `.github/ISSUE_TEMPLATE/rfc.yml` | Requires the `RFC` label. Also hardcodes `projects: ["webinertia/"]` — retarget or drop |
| `renovate-config.json` | Only if you use Renovate. Requires `renovate`, `Awaiting Maintainer Response`, `security` |
| `.github/PULL_REQUEST_TEMPLATE.md`, `SECURITY.md`, `README.md` | Plain templates, no label dependency |
| `renovate.md` | Documentation for the Renovate setup |

**Not needed:** `scripts/setup-org-security.sh` — unrelated to label sync.

### Trim `labels.yml` for your org

The webinertia list is 42 labels and includes webware-ecosystem families you probably
don't want (`mago-analysis`, `mago-fmt`, `mago-lint`, `db: MySQL`/`Postgres`/`SQLite`,
`ims-migration`, `version: Next Major`/`Minor`/`Patch`, `tooling-alignment`). Keep the
generic ones (`bug`, `enhancement`, `priority: *`, `status: *`, `needs: *`, …).

Whatever you keep, every label referenced by your issue templates or Renovate config
**must** exist in `labels.yml` — the script deletes every label the file does not
define, so a missing name silently removes it from all repos.

---

## Why you need your own app

A GitHub App registration is owned by exactly one account. A **private** app "can only
be installed on the account that owns the app", so `webinertia-label-sync` cannot be
installed on your org. Making it public would let you install it, but it would not help
you: minting an installation token requires the app's **private key**, which only the
owner holds. The app is purely a credential — the logic is the three files above — so
each org registers its own copy.

This also means: **never share a `.pem`.** A GitHub App private key is not scoped to one
org; it authenticates as the app against *every* installation of it.

---

## 1. Create the app

Org settings → **Developer settings** → **GitHub Apps** → **New GitHub App**.

| Field | Value |
| ----- | ----- |
| GitHub App name | Must be globally unique across GitHub — `yourorg-label-sync` |
| Homepage URL | `https://github.com/YOURORG/.github` |
| Webhook → Active | **Uncheck.** No events are needed; the app is used only for its token |
| Where can this app be installed? | **Only on this account** is fine — no need to make it public |

Under **Repository permissions**:

- **Metadata** → Read-only (mandatory, pre-selected)
- **Issues** → Read and write (this is what grants label create/edit/delete)

Then:

1. **Create GitHub App**
2. Copy the **Client ID** from the app's General page — *not* the App ID. The workflow
   reads the client ID because App IDs can change if an app is ever transferred.
3. **Generate a private key** → downloads a `.pem`. This is shown once; store it safely.
4. **Install App** → your org → **All repositories**. Selected-repos mode will not work:
   the script fans out over every non-archived, non-fork repo in the org.

### Alternative: register from a manifest

The [manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
pre-fills all of the above, so the person adopting it only has to name the app. It needs
a page to POST the manifest and a redirect target to exchange the returned `code` for
the PEM (both within one hour):

```html
<form action="https://github.com/organizations/YOURORG/settings/apps/new?state=abc123" method="post">
  <input type="hidden" name="manifest" id="manifest">
  <input type="submit" value="Register label sync app">
</form>
<script>
  document.getElementById("manifest").value = JSON.stringify({
    name: "yourorg-label-sync",
    url: "https://github.com/YOURORG/.github",
    public: false,
    default_permissions: { issues: "write", metadata: "read" },
    default_events: []
  });
</script>
```

Omit `hook_attributes` entirely — there is no webhook. The resulting app is owned by
whoever completes the flow; hand the PEM and client ID back to the workflow setup below.
The name still has to be globally unique.

---

## 2. Store the credentials on the `.github` repo

On `YOURORG/.github` → **Settings** → **Secrets and variables** → **Actions**
(org-level works too, and the repo inherits it):

| Kind | Name | Value |
| ---- | ---- | ----- |
| Variable | `LABEL_SYNC_APP_CLIENT_ID` | The app's client ID |
| Secret | `LABEL_SYNC_APP_PRIVATE_KEY` | Full contents of the `.pem`, including the BEGIN/END lines |

A repository **variable**, not a secret, for the client ID — that is deliberate, so the
token step can be gated on it. Until `LABEL_SYNC_APP_CLIENT_ID` exists the workflow
no-ops with a warning rather than failing, so it is safe to commit the workflow before
the app exists.

Optionally set variable `LABEL_SYNC_DRY_RUN` to `true` for the first run.

---

## 3. First run

**Actions** → **Label Sync** → **Run workflow** with **dry-run** checked. The log prints
`(dry-run) gh label create ...` for everything it *would* do, touching nothing.

Confirm the repo list and label set look right, then run again with dry-run unchecked
(or unset `LABEL_SYNC_DRY_RUN`). After that the workflow keeps itself in sync:

- on any push to `master` touching `labels.yml`, the workflow, or the script
- weekly, Mondays 06:00 UTC, as a drift safety net
- on demand via **Run workflow**

To edit the label set, change `.github/labels.yml` and push — that alone triggers a sync.

---

## 4. Adjusting the script

`scripts/sync-labels.sh` is deliberately single-org. Two edits:

```bash
org="YOURORG"        # was: webinertia

renames=(            # was: webinertia's retired-label history
    "OldLabel|new label"
)
```

Clear `renames` for a fresh org: it exists only to re-label open items off labels that
webinertia retired (`Urgent` → `priority: Critical`, `BugFix` → `bug`, …) before deleting
them. On a new org those names don't exist, so an empty array is correct. Add a pair
later if you rename a label and want open items carried across.

Also raise `gh repo list "$org" --limit 400` if your org has more repos than that.

Other behaviour worth knowing:

- Needs `gh` and `python3`. The script installs PyYAML itself if it is missing.
- Idempotent — running twice changes nothing.
- Renames a label in place when only its casing drifted, so issue associations survive.
- **Deletes** every label not defined in `labels.yml`, in every repo. This drops the
  label from closed items too (open ones are re-labelled first if listed in `renames`).
- The token needs rights on every repo; in CI that is the app installation token. Locally
  a personal token with `repo` scope is enough, and the script can be run by hand:
  `GH_TOKEN=... ./scripts/sync-labels.sh .github/labels.yml --dry-run`

---

## 5. Who can install it

Only owners of the org (and designated app managers) can install a GitHub App on an org,
and only the app's owner can mint tokens for it. If you are handing this setup to someone
else, they need org-owner rights on the app creation and installation steps.
