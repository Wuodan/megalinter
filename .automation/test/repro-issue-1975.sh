#!/usr/bin/env bash
set -euo pipefail

# Reproduces issue #1975:
# run mega-linter-runner in fix mode on a tiny temporary workspace and
# compare the host-side file ownership before and after the container run.

# Usage:
#   ./.automation/test/repro-issue-1975.sh
#   ./.automation/test/repro-issue-1975.sh --docker-user
#   ./.automation/test/repro-issue-1975.sh --docker-user-home
#
# Environment:
#   MEGALINTER_IMAGE: override the image to run
#   MEGALINTER_NO_DOCKER_PULL=true: skip docker pull in runner mode
#
# The default mode uses mega-linter-runner, matching normal local usage.
# --docker-user runs docker directly with --user "$(id -u):$(id -g)" to test
# whether explicit UID/GID mapping fixes report file ownership.
# --docker-user-home does the same, but also sets HOME to a writable directory
# inside the mounted workspace.

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
# trap cleanup EXIT

# Minimal MegaLinter config: enable a formatter that will rewrite invalid YAML.
cat >"$tmpdir/.mega-linter.yml" <<'YAML'
ENABLE_LINTERS:
  - YAML_PRETTIER
UPDATED_SOURCES_REPORTER: false
TEXT_REPORTER: true
YAML

# Deliberately badly formatted YAML so fix mode has something to rewrite.
cat >"$tmpdir/bad.yaml" <<'YAML'
foo:    bar
YAML

before_owner="$(stat -c '%u:%g %n' "$tmpdir/bad.yaml")"
before_file="$(cat "$tmpdir/bad.yaml")"
image="${MEGALINTER_IMAGE:-ghcr.io/oxsecurity/megalinter:beta}"

if [[ "${1:-}" == "--docker-user" ]]; then
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    -v "$tmpdir:/tmp/lint:rw" \
    -e APPLY_FIXES=all \
    "$image" \
    > /dev/null
elif [[ "${1:-}" == "--docker-user-home" ]]; then
  mkdir -p "$tmpdir/.home"
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    -v "$tmpdir:/tmp/lint:rw" \
    -e HOME=/tmp/lint/.home \
    -e APPLY_FIXES=all \
    "$image" \
    > /dev/null
else
  # Run the normal local Docker-based execution path with autofix enabled.
  runner_args=(--path "$tmpdir" --fix)
  if [[ "${MEGALINTER_NO_DOCKER_PULL:-}" == "true" ]]; then
    runner_args+=(--nodockerpull)
  fi
  if [[ -n "${MEGALINTER_IMAGE:-}" ]]; then
    runner_args+=(--image "$MEGALINTER_IMAGE")
  else
    runner_args+=(--release beta)
  fi
  mega-linter-runner "${runner_args[@]}" \
    > /dev/null
fi

after_owner="$(stat -c '%u:%g %n' "$tmpdir/bad.yaml")"
after_file="$(cat "$tmpdir/bad.yaml")"

echo "Workspace: $tmpdir"
echo "Before: $before_owner"
echo "After:  $after_owner"
echo
echo "Before file:"
echo "---"
echo "${before_file}"
echo "---"
echo
echo "After file:"
echo "---"
echo "${after_file}"
echo "---"

ls -alh "$tmpdir"
find "$tmpdir" -printf '%M %u:%g %p\n' | sort
