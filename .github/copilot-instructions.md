# Homebridge VM Image Builder

Builds a Debian 13 disk image with Homebridge installed, for arm64 and amd64, and packages it for UTM, VirtualBox and Hyper-V.

`README.md` ("Developer Documentation") is the full description: the scripts, the release stages and what must not change by accident. Read it first. This file only adds what helps when changing code.

## Rules

- **Never** run `build-debian-image.sh`, `scripts/package-for-*.sh` or `scripts/convert-img-to-virtual-disk.sh` directly on a development machine. They need root rights and use loop devices. Use `scripts/local-build-in-docker.sh`.
- Do not change release tags, release file names, or the paths listed under "What must not change by accident" in `README.md`.
- `assets/01-homebridge/files/hb-config` is a `/bin/sh` script (dash). No bash-only syntax. Set `HB_CONFIG_VERSION` to the date when the file changes.
- `assets/01-homebridge/files/vm-env.sh` and `source-vm.sh` are loaded by `/bin/sh` scripts of the Homebridge apt package. Plain sh only, and they must print nothing.
- Anything that must differ per VM (keys, ids) is removed in `scripts/seal-image.sh` and made on the first start. Never add such a thing to the image.
- Workflows: `permissions: {}` at the top, rights per job, actions pinned by commit, and workflow values passed to shell lines through `env:`, never pasted into the line. `tests/test-workflows.sh` checks this.

## Checking a change

1. Script tests (about a minute; see `tests/README.md` for the Docker command): `tests/run.sh`
2. Lint: `scripts/lint.sh` (shellcheck). Workflows: `actionlint`.
3. When the image changes: build it and run the boot test.
   ```bash
   ./scripts/local-build-in-docker.sh arm64 stable
   ```
   The boot test (`scripts/boot-test.sh`) starts the image under QEMU and runs `scripts/boot-test-checks.sh` inside it. Add a check there for anything that can only be seen in a running system.

Every fix needs a test that fails without it.

## How the build works

`build-debian-image.sh <arm64|amd64> [stable|beta|alpha] [release tag]`:

1. Makes a 5 GB raw disk image with a GPT partition table: a 256 MB EFI partition and an ext4 root partition.
2. `debootstrap` installs the Debian base system. Debian's signature on it is checked; a failed check stops the build.
3. `scripts/chroot-base-setup.sh` runs inside the new system: package sources, kernel, GRUB (EFI), system packages, fstab.
4. Each folder in `assets/` is one stage, run in name order: `00-packages` lists packages, `NN-run.sh` scripts copy files and run commands inside the new system with `on_chroot`.
5. The manifest is written, and `scripts/seal-image.sh` removes what must not be in the image.

Times: about 2 to 4 minutes for a build on a machine of the same CPU type, and 2 to 5 minutes for the boot test without KVM.

## Releases

Fully automatic: Stage 1 (daily, dependency bot) → Stage 2 (build + boot test) → Stage 3 (release, disk formats) → Stage 4 (UTM, VirtualBox, Hyper-V packages). A failed stage fails the stage before it. Nothing is published unless the boot test passed. Details are in `README.md`.

**Pre-release Branches (beta and alpha only):**
- By default every stream builds from the `latest` branch.
- To ship unmerged work to beta or alpha without touching stable, create a branch named `<stream>-YYYY.M.D` from `latest` (date it was created, dots, no zero padding, e.g. `beta-2026.11.18`) and merge the feature PR into it with a normal merge (not squash), so the release notes list its commits.
- Stage 1 picks the newest branch matching `<stream>-YYYY.M.D` (by `sort -V`), points the dependency bot at it (`base_branch`) and runs Stage 2 on it. Stage 2 runs Stage 3 on the same branch, and Stage 3 runs the Stage 4 packaging workflows on it. With no such branch, the stream uses `latest`.
- Dots, not dashes: release tags are `beta-YYYY-MM-DD`, and a branch with the same name would make git refs ambiguous.
- Stage 2 and Stage 3 refuse to build stable from anything but `latest`, and refuse beta/alpha from any branch other than `latest` or `<stream>-YYYY.M.D`.
- Stage 1 only starts a build when the dependency bot changed something. To ship a new branch straight away, run Stage 2 by hand on that branch.
- Keep the branch current by merging `latest` into it from time to time. While the branch exists, `<stream>/package.json` updates land on the branch, not on `latest`.
- Retire it (feature merged into `latest`, or abandoned) by renaming it to `archive/<stream>-YYYY.M.D`. It then stops matching and the stream returns to `latest`, while the history stays browsable. Don't archive as a tag: the cleanup action prunes old beta/alpha tags.
- The branch needs the same ruleset bypass as `latest` so the dependency bot App can push to it.

