#!/usr/bin/env bash
# Old beta and alpha releases are deleted, the newest five stay. The choice must go by the
# exact tag form of the stream, and nothing may be deleted before the new release is complete.
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

PICK="$REPO/.github/actions/cleanup-old-releases-and-tags/old-releases.sh"
old() { printf '%s\n' "${TAGS[@]}" | "$PICK" "$1" "$2" | tr '\n' ' '; }

TAGS=(beta-2026-11-07 2026-11-01 alpha-2026-11-06 beta-2026-11-06 beta-2026-11-05 beta-2026-11-04 beta-2026-11-03 beta-2026-11-02 beta-2026-10-30 2026-10-29 v0.0.1 alpha-2026-11-05)

same "beta: the newest five stay, the two older ones are picked" "$(old beta 5)" "beta-2026-11-02 beta-2026-10-30 "
same "alpha: two releases and five to keep, nothing is picked" "$(old alpha 5)" ""
same "alpha: keep one, the older one is picked" "$(old alpha 1)" "alpha-2026-11-05 "
same "stable tags are only picked for the stable stream" "$(old stable 1)" "2026-10-29 "

TAGS=(beta-2026-11-07 alpha-beta-test my-beta-2026-11-01 beta-2026-11-06x beta-2026-11-05 beta beta- betamax-2026-11-01)
same "a tag that only has the word beta in it is never picked" "$(old beta 1)" "beta-2026-11-05 "

TAGS=(beta-2026-11-07)
isnt "a stream it does not know is refused" "$PICK" 'beta|alpha' 5
isnt "keeping zero releases is refused" "$PICK" beta 0
isnt "a number with other characters is refused" "$PICK" beta '5; x'

python3 - "$REPO/.github/workflows/release-stage-3_package_release.yml" > "$W/facts" <<'PYTHON'
import sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
print("cleanup-needs", jobs["cleanup-old-releases-and-tags"]["needs"])
PYTHON
has "old releases are only deleted after the packaging workflows passed" "$W/facts" "cleanup-needs ['wait-for-appliance-packaging']"
has "the action uses the script to pick" "$REPO/.github/actions/cleanup-old-releases-and-tags/action.yml" 'old-releases.sh" "$RELEASE_TYPE" "$RELEASES_TO_KEEP"'

finish
