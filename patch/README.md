# Patch Directory

This directory stores local patches for `managed_components`.

## Directory convention

- Put component patches under `patch/<component_name>/`.
- One patch file per logical change, for example:
  - `patch/espressif__iot_bridge/0001-xxx.patch`
  - `patch/espressif__iot_bridge/0002-yyy.patch`
- Keep patch filenames ordered by number so apply/revert order is deterministic.

## Current status

- `espressif__iot_bridge`: local patches exist.
- Other managed components: no local differences against official checksums.
- Detailed report: `patch/component-diff-report.md`

## How to apply patches

From project root (`NanoS/`):

```bat
patch\apply_patches.bat
```

What it does:

- Recursively scans `patch/**/*.patch`.
- Infers component name from patch parent folder.
- Applies patch into `managed_components/<component_name>`.
- Skips patch if already applied.

Exit code:

- `0`: all good (applied or skipped)
- `1`: environment error (missing git or managed_components)
- `2`: one or more patches failed

## How to revert patches

From project root (`NanoS/`):

```bat
patch\revert_patches.bat
```

What it does:

- Recursively scans `patch/**/*.patch`.
- Reverts each patch with `git apply --reverse`.
- Skips patch if not currently applied.

Exit code:

- `0`: all good (reverted or skipped)
- `1`: environment error
- `2`: one or more reverts failed

## Typical workflow

1. Pull or regenerate dependencies (`managed_components`).
2. Run `patch\apply_patches.bat`.
3. Build and test.
4. If needed, restore official state with `patch\revert_patches.bat`.

## Notes

- Scripts require `git` in `PATH`.
- Scripts are designed for Windows `cmd`.
- If a patch fails after component upgrade, regenerate the patch for the new upstream version.
