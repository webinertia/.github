# Renovate in the Webinertia organisation

Every repository Renovate manages extends one shared preset:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["local>webinertia/.github:renovate-config"]
}
```

`renovate-config.json` in this repository is the single source of that preset — change behaviour
here, once, rather than per repository. A `renovate.json` that does not extend it (for example the
`config:recommended` default the onboarding flow writes when the app's onboarding config is unset)
silently opts that repository out of everything below.

## What the preset does

- **Webware components always move to the latest release.** `webware/**` and `webinertia/**` are
  updated with `rangeStrategy: replace`, so a new release rewrites the constraint to the new floor
  (`^2.0.0-alpha.1`). Widening is deliberately *not* used for these packages:
  - it turns a constraint into an OR-range (`^1.0 || ^2.0`);
  - `prefer-stable` then resolves any lock refresh *back* to the older stable line;
  - and the next release appends a duplicate alternative (`^1.0 || ^2.0 || ^2.0`).

  The components ship as one release train, so supporting the previous major alongside the new one
  is not wanted. A package that genuinely needs two majors at once needs its own rule.
- Everything else keeps the default `replace`, except `require` dependencies, which are widened.
- Webware updates are grouped into a single PR ("Webware packages") and track prereleases
  (`ignoreUnstable: false`, `respectLatest: false`).
- PHP is held to `^8.4.1`, grouped, and never automerged.
- Lock file maintenance runs weekly. It re-resolves *within* existing constraints, so it can never
  move a dependency across a major line — only a constraint change does that, and only Renovate
  raises one.
- `automerge` and `platformAutomerge` are off: every update is a pull request a maintainer merges.
- Vulnerability fix PRs are labelled `security` and are never automerged.

## Constraints

Never write an OR-range for a webware dependency (`^1.0 || ^2.0`). Use a single floor at the tag in
use (`^1.0.0-alpha.2`). Two reasons: an OR-range is what lets `prefer-stable` resolve an older
stable line, and the `lowest` CI leg resolves the *floor*, so the floor has to be the tag the
package is actually validated against.

## Adding a repository

Give it a `renovate.json` extending `local>webinertia/.github:renovate-config`. If Renovate has
already opened a "Configure Renovate" onboarding PR containing `config:recommended`, that is the
app default, not this organisation's policy — correct it before merging.
