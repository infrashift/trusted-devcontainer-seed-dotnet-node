#!/bin/sh
# Report how far this repository's feature pins have drifted behind the trusted
# line. NETWORKED: it asks the registry what `latest` resolves to today.
#
# WHY THIS EXISTS. A pinned digest stays pullable long after the tag moved past
# it, so a seed keeps building perfectly while falling further behind, and
# nothing anywhere says so. This one sat two days and four features stale
# without a signal, and the staleness was noticed only because someone compared
# the pins by hand while chasing something else (2026-09-17).
#
# WHY IT WARNS RATHER THAN FAILS. A pin being old is not a defect -- immutability
# is the point of pinning, and a seed is entitled to sit on a digest it has
# tested. Failing a build on a number that changes when someone ELSE releases
# would make an unrelated repository's merge break this one. `--strict' turns
# the report into a failure for a caller that does want the gate, and nothing
# in the golden workflow passes it.
#
# Exit codes: 0 always, unless --strict and at least one pin is behind.
set -eu

. "$(dirname "$0")/lib.sh"
SFD_STEP=check-pins

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

CONF=.devcontainer/devcontainer.json
[ -f "$CONF" ] || fail "no ${CONF} here"

command -v jq >/dev/null 2>&1 || fail "jq is needed to read ${CONF}"
command -v curl >/dev/null 2>&1 || fail "curl is needed to ask the registry"

behind=0
current=0
unknown=0

# Feature keys look like ghcr.io/<owner>/<repo>/<name>@sha256:<digest>. Anything
# else in `features' is not ours to check.
for ref in $(jq -r '.features | keys[]' "$CONF"); do
  case "$ref" in
    ghcr.io/*@sha256:*) ;;
    *) continue ;;
  esac

  repo=${ref%@*}                 # ghcr.io/owner/repo/name
  pinned=${ref#*@}               # sha256:...
  path=${repo#ghcr.io/}          # owner/repo/name
  name=${path##*/}

  token=$(curl -sf "https://ghcr.io/token?scope=repository:${path}:pull&service=ghcr.io" \
            | jq -r '.token // empty' 2>/dev/null || true)
  if [ -z "$token" ]; then
    warn "${name}: could not get a pull token; skipped"
    unknown=$((unknown + 1))
    continue
  fi

  # HEAD the tag and read the digest the registry reports for it. Never GET the
  # manifest and hash it -- the registry's own answer is the comparison a
  # consumer would make.
  latest=$(curl -sfI -H "Authorization: Bearer ${token}" \
             -H "Accept: application/vnd.oci.image.manifest.v1+json" \
             "https://ghcr.io/v2/${path}/manifests/latest" 2>/dev/null \
             | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest:[[:space:]]*//p')
  if [ -z "$latest" ]; then
    warn "${name}: registry did not report a digest for :latest; skipped"
    unknown=$((unknown + 1))
    continue
  fi

  if [ "$latest" = "$pinned" ]; then
    current=$((current + 1))
  else
    behind=$((behind + 1))
    printf '[%s] BEHIND %-12s pinned %s  latest %s\n' \
      "$SFD_STEP" "$name" "$(echo "$pinned" | cut -c1-19)" "$(echo "$latest" | cut -c1-19)"
  fi
done

log "${current} pin(s) current, ${behind} behind, ${unknown} not checked"

if [ "$behind" -gt 0 ]; then
  log "a behind pin is not broken -- it still pulls, and it is still the digest this repository tested."
  log "to move: crane digest ghcr.io/<owner>/<repo>/<name>:latest, then edit ${CONF} and re-run make test."
  [ "$STRICT" -eq 1 ] && fail "${behind} pin(s) behind and --strict was given"
fi

exit 0
