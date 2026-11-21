#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# Rules for the workflow files: who gets which rights, how values reach shell lines, and that
# code from outside is named by a commit.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

WORKFLOWS="$REPO/.github/workflows"
ACTIONS="$REPO/.github/actions"

# every "uses:" line of every workflow and local action, as "file:line: target"
uses() {
  grep -rnE '^\s*(-\s+)?uses:' "$WORKFLOWS" "$ACTIONS" --include='*.yml' \
    | sed -E "s#^$REPO/##; s/^([^:]+:[0-9]+):\s*(-\s+)?uses:\s*['\"]?([^'\" ]+)['\"]?.*/\1: \3/"
}

# A tag or a branch name can be moved to other code by its owner. A full commit id can not.
# Only the organisation's own dependency bot and this repo's own actions are named another way.
while read -r where target; do
  case "$target" in
    ./* | homebridge/*) continue ;;
  esac
  if [[ "$target" =~ @[0-9a-f]{40}$ ]]; then
    ok "named by commit: $target (${where%:})"
  else
    fail "named by commit: $target" "$where"
  fi
done < <(uses)

# The rights of each job, and how values reach shell lines. Read from the YAML itself.
python3 - "$WORKFLOWS" "$ACTIONS" > "$W/workflow-facts" <<'PYTHON'
import glob, os, sys, yaml

workflows, actions = sys.argv[1], sys.argv[2]

for path in sorted(glob.glob(os.path.join(workflows, "*.yml"))):
    name = os.path.basename(path)
    data = yaml.safe_load(open(path))
    print(f"top {name} {data.get('permissions', 'MISSING')!r}")
    for job_id, job in data["jobs"].items():
        rights = job.get("permissions", {})
        text = ",".join(f"{key}:{value}" for key, value in sorted(rights.items())) or "none"
        print(f"job {name} {job_id} {text}")
        token_step = None
        for index, step in enumerate(job.get("steps", [])):
            if "${{" in str(step.get("run", "")):
                print(f"expr {name} {job_id} step {index + 1} ({step.get('name', '')})")
            if "create-github-app-token" in str(step.get("uses", "")) and token_step is None:
                token_step = index
        if token_step is not None:
            # what runs in the same job AFTER the token that can write was made
            later = [str(step.get("run", "")) + str(step.get("uses", "")) for step in job["steps"][token_step + 1:]]
            installs = any(word in text for text in later for word in ("choco install", "brew install", "apt-get install", "install-virtualbox", "pip install"))
            print(f"token {name} {job_id} installs-after-token={installs}")

for path in sorted(glob.glob(os.path.join(actions, "*", "action.yml"))):
    data = yaml.safe_load(open(path))
    for index, step in enumerate(data["runs"]["steps"]):
        if "${{" in str(step.get("run", "")):
            print(f"expr {os.path.basename(os.path.dirname(path))} step {index + 1} ({step.get('name', '')})")
PYTHON
same "the workflow files could be read" "$?" "0"

# every workflow starts with no rights at all; jobs then ask for what they need
same "every workflow gives no rights by default" "$(grep -c '^top ' "$W/workflow-facts")" "$(grep -c "^top .* {}$" "$W/workflow-facts")"

# job_rights <workflow file> <job> <expected rights>
job_rights() {
  same "$1 / $2 has these rights: $3" "$(sed -n "s/^job $1 $2 //p" "$W/workflow-facts")" "$3"
}
S1=release-stage-1_update_dependencies.yml
S2=release-stage-2_build_and_push_images.yml
S3=release-stage-3_package_release.yml
job_rights ci.yml tests "contents:read"
job_rights ci.yml build-host-packages "contents:read"
job_rights $S1 define-matrix "none"
job_rights $S1 update-dependencies "actions:write,contents:read"
job_rights $S2 set-versions "none"
job_rights $S2 build-img-file "contents:read"
job_rights $S2 invoke-package-and-release "actions:write,contents:read"
job_rights $S3 create-release "actions:read,contents:read"
job_rights $S3 invoke-appliance-packaging "actions:write"
job_rights $S3 wait-for-appliance-packaging "actions:read"
job_rights $S3 cleanup-old-releases-and-tags "contents:read"
job_rights $S3 finalize-stable-release "none"
for kind in hyperv:package-for-hyperv utm:package-for-utm-vm virtualbox:package-for-virtual-box; do
  job_rights "release-stage-4_package-for-${kind%%:*}.yml" "${kind##*:}" "actions:read,contents:read"
  job_rights "release-stage-4_package-for-${kind%%:*}.yml" publish-to-release "none"
done
same "every job is in the list above" "$(grep -c '^job ' "$W/workflow-facts")" "18"

# A value pasted into a shell line becomes shell code. Values must come in through "env:".
same "no shell line has a \${{ }} value pasted into it" "$(grep '^expr ' "$W/workflow-facts")" ""

# The token that can write to releases must not share a job with programs installed from outside.
same "no job installs programs after it made the token that can write" "$(grep -c 'installs-after-token=True' "$W/workflow-facts")" "0"
for kind in hyperv utm virtualbox; do
  same "Stage 4 ${kind}: only the publish job makes the token that can write" \
    "$(sed -n "s/^token release-stage-4_package-for-${kind}.yml \([a-z-]*\) .*/\1/p" "$W/workflow-facts" | tr '\n' ' ')" "publish-to-release "
done

isnt "no workflow uses the personal access token GH_TOKEN" grep -rq 'secrets\.GH_TOKEN' "$WORKFLOWS" "$ACTIONS"
same "every App token names the one right it needs" \
  "$(grep -rc 'uses: actions/create-github-app-token' "$WORKFLOWS" | awk -F: '{n += $2} END {print n}')" \
  "$(grep -rc 'permission-contents: write' "$WORKFLOWS" | awk -F: '{n += $2} END {print n}')"

has "the VirtualBox signing key is only used when it has the expected fingerprint" "$ACTIONS/install-virtualbox/action.yml" 'if [[ "$FOUND_FINGERPRINT" != "$ORACLE_KEY_FINGERPRINT" ]]; then'

finish
