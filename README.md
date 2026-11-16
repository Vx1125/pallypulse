# PallyPulse

Paladin blessings for WoW Forever: one-button smart buffing (in combat too), spec-aware
assignments, auras, Oath of Light, party-frame icons and PallyPower sync.

CurseForge project: 1809219

## Releasing

1. Update `CHANGELOG.md`.
2. Commit, then tag and push: `git tag v1.0.2 && git push origin main --tags`
3. The GitHub Action packages the addon and uploads it to CurseForge.

Needs the repository secret `CF_API_KEY` (a CurseForge API token), and
Settings > Actions > General > Workflow permissions set to "Read and write".

## Commands

`/pulse` window, `/pulse players`, `/pulse versions`, `/pulse options`, `/pulse test`,
`/pulse trace`, `/pulse debug`, `/pulse frames`
