# Tests

Small shell tests for the scripts in this repo. They run on every pull request (`.github/workflows/ci.yml`).

## Run them

The tests are made for Linux. On a Mac or on Windows, run them in a Debian container:

```bash
docker run --rm -v "$PWD":/repo:ro -w /repo debian:trixie-slim bash -c '
  apt-get update -qq &&
  apt-get install -y -qq --no-install-recommends bash ca-certificates dash git jq nginx openssl passwd python3 python3-yaml > /dev/null &&
  git config --global --add safe.directory /repo &&
  tests/run.sh'
```

One test file only: `tests/run.sh nginx` (any part of the file name).

## How a test works

- It copies a script from the repo into a scratch folder.
- It moves the system paths in the copy (`/etc/...`, `/var/...`) into that folder.
- It puts fake commands (`systemctl`, `curl`, `apt-get` ...) first on the `PATH`.
- It runs the copy and looks at the result.

Nothing on the machine that runs the tests is changed, and no root rights are needed.

## What the tests do not cover

- A full image build and a boot. `scripts/boot-test.sh` does that in the release workflow, before anything is published.
- The Hyper-V, VirtualBox and UTM packages. They need Windows, VirtualBox or a Mac.
