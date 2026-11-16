# PallyPulse

Paladin blessings for WoW Forever: one-button smart buffing (in combat too), spec-aware
assignments, auras, Oath of Light, party-frame icons and PallyPower sync.

CurseForge project: 1809219

## Releasing

1. Update `CHANGELOG.md`.
2. Put the new version number in `VERSION` (e.g. `1.0.2`) and push to `main`.
   The GitHub Action tags `v1.0.2`, packages the addon and uploads it to CurseForge.
   (Pushing or creating a `v1.0.2` tag on GitHub works too.)

Needs the repository secret `CF_API_KEY` (a CurseForge API token), and
Settings > Actions > General > Workflow permissions set to "Read and write".

## Commands

`/pulse` window, `/pulse players`, `/pulse versions`, `/pulse options`, `/pulse test`,
`/pulse trace`, `/pulse debug`, `/pulse frames`
