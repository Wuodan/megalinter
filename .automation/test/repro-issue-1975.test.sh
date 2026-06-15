#!/usr/bin/env bash
set -euo pipefail

# Run the issue #1975 repro before and after applying a commit that changes
# container-side code such as entrypoint.sh.
#
# This script always rebuilds the same local image tag so the repro runs
# against the code currently checked out in the working tree.

image="megalinter-local:quick"
commit="${1:-9477f7cb}"

rebuild_image() {
  docker buildx build \
    --platform linux/amd64 \
    --load \
    -f Dockerfile-quick \
    -t "$image" \
    .
}

#git revert --no-edit "$commit"
#
## before
#make bootstrap
#rebuild_image
#prefix="before-change"
#
## normal mode: run with normal megalinter code
##
## result:
## - files created (not changed) by megalinter are owned by root
#MEGALINTER_IMAGE="$image" \
#MEGALINTER_NO_DOCKER_PULL=true \
#.automation/test/repro-issue-1975.sh \
#  &>".automation/test/repro-issue-1975.${prefix}.normal.log"
#
## docker-user mode: runs docker directly with
## `--user "$(id -u):$(id -g)"`
## to test
##
## result:
## - files created (not changed) by megalinter are owned by host user
## - error: could not lock config file //.gitconfig: Permission denied
#MEGALINTER_IMAGE="$image" \
#.automation/test/repro-issue-1975.sh --docker-user \
#  &>".automation/test/repro-issue-1975.${prefix}.docker-user.log"
#
## docker-user mode: runs docker directly with
## `--user "$(id -u):$(id -g)"`
## and a writable user home
## to test
##
## result:
## - files created (not changed) by megalinter are owned by host user
## - no permission denied error
#MEGALINTER_IMAGE="$image" \
#.automation/test/repro-issue-1975.sh --docker-user-home \
#  &>".automation/test/repro-issue-1975.${prefix}.docker-user-home.log"
#
## add change
#git cherry-pick "$commit"

# after
make bootstrap
rebuild_image
prefix="after-change"

# normal mode: run with normal megalinter code
#
# result:
# - files created (not changed) by megalinter are owned by host user
# - no permission denied error
MEGALINTER_IMAGE="$image" \
MEGALINTER_NO_DOCKER_PULL=true \
.automation/test/repro-issue-1975.sh \
  &>".automation/test/repro-issue-1975.${prefix}.normal.log"
