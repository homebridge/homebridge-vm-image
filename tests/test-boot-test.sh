#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for, or passed on, as it is
# The boot test is the gate before a release: a failed check, a VM that never answers and a
# check that never ends must all stop the release.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

GUEST="$REPO/scripts/boot-test-guest.py"

# A stand-in for the guest agent of a VM: it answers on a socket file like the real one.
# MODE=ok: runs the script it is given with bash, and reports output and exit code.
# MODE=silent: never answers.  MODE=never-ends: the script never "exits".
cat > "$W/agent.py" <<'PYTHON'
import base64, json, os, socket, subprocess, sys
path, mode = sys.argv[1], sys.argv[2]
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(1)
connection, _ = server.accept()
reader = connection.makefile("rb")
result = None
for line in reader:
    if mode == "silent":
        continue
    request = json.loads(line)
    name, arguments = request["execute"], request.get("arguments", {})
    if name == "guest-sync":
        answer = {"return": arguments["id"]}
    elif name == "guest-exec":
        script = base64.b64decode(arguments["input-data"])
        result = subprocess.run([arguments["path"]] + arguments["arg"], input=script, capture_output=True)
        answer = {"return": {"pid": 42}}
    elif name == "guest-exec-status":
        if mode == "never-ends":
            answer = {"return": {"exited": False}}
        else:
            answer = {"return": {"exited": True, "exitcode": result.returncode,
                                 "out-data": base64.b64encode(result.stdout).decode(),
                                 "err-data": base64.b64encode(result.stderr).decode()}}
    else:
        answer = {"error": {"class": "CommandNotFound"}}
    connection.sendall(b"\xff" + json.dumps(answer).encode() + b"\n")
PYTHON

# with_agent <mode> <script text> <wait for VM> <wait for script> [args]: sets $code and $W/out
with_agent() {
  local mode="$1" script="$2" wait_vm="$3" wait_script="$4"
  shift 4
  rm -f "$W/agent.sock"
  printf '%s\n' "$script" > "$W/script.sh"
  python3 "$W/agent.py" "$W/agent.sock" "$mode" &
  local agent=$!
  while [ ! -S "$W/agent.sock" ]; do sleep 0.1; done
  python3 "$GUEST" "$W/agent.sock" "$W/script.sh" "$wait_vm" "$wait_script" "$@" > "$W/out" 2> "$W/err"
  code=$?
  kill "$agent" 2> /dev/null
  wait "$agent" 2> /dev/null
}

with_agent ok 'echo "hello from $1"; exit 0' 20 20 inside
same "a passing script gives code 0" "$code" "0"
same "its output is printed, and it got its argument" "$(cat "$W/out")" "hello from inside"

with_agent ok 'echo "FAIL  something"; exit 1' 20 20
same "a failed check in the VM gives code 1" "$code" "1"
has "the failed check is printed" "$W/out" "FAIL  something"

with_agent silent 'exit 0' 4 20
same "a VM that never answers gives code 98, not success" "$code" "98"

with_agent never-ends 'exit 0' 20 6
same "a check that never ends gives code 99, not success" "$code" "99"

is "the checks script is valid bash" bash -n "$REPO/scripts/boot-test-checks.sh"
is "the boot test script is valid bash" bash -n "$REPO/scripts/boot-test.sh"
isnt "the boot test refuses an image file that does not exist" "$REPO/scripts/boot-test.sh" "$W/none.img" arm64
isnt "the boot test refuses a CPU type it does not know" "$REPO/scripts/boot-test.sh" "$W/script.sh" riscv

# where the gate sits in the release workflows
python3 - "$REPO/.github/workflows" > "$W/facts" <<'PYTHON'
import os, sys, yaml
folder = sys.argv[1]
stage2 = yaml.safe_load(open(os.path.join(folder, "release-stage-2_build_and_push_images.yml")))
steps = [step.get("name", "") for step in stage2["jobs"]["build-img-file"]["steps"]]
print("order", steps.index("run build-debian-image.sh script") < steps.index("Boot test") < steps.index("Upload Homebridge Image"))
boot = stage2["jobs"]["build-img-file"]["steps"][steps.index("Boot test")]
# the only condition allowed: amd64 only (GitHub's arm runners have no KVM to boot arm64 with)
print("boot-can-fail", "continue-on-error" not in boot and boot.get("if") in (None, "matrix.arch == 'amd64'"))
print("release-needs-build", "build-img-file" in stage2["jobs"]["invoke-package-and-release"]["needs"])
stage3 = yaml.safe_load(open(os.path.join(folder, "release-stage-3_package_release.yml")))
print("latest-needs", stage3["jobs"]["finalize-stable-release"]["needs"])
PYTHON
has "the boot test runs after the build and before the image is uploaded" "$W/facts" "order True"
has "a failed boot test fails the build job" "$W/facts" "boot-can-fail True"
has "the release (Stage 3) is only started after the build job passed" "$W/facts" "release-needs-build True"
has "stable becomes latest only after the packaging workflows passed" "$W/facts" "latest-needs ['wait-for-appliance-packaging']"

finish
