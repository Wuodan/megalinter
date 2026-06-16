# Open Questions

## Why start sshd

`sshd` is not part of the normal MegaLinter run path. It is only started when
`MEGALINTER_SSH=true` is set in `entrypoint.sh`.

`EXPOSE 22` and `/root/docker_ssh` are present in many images, but that alone
does not publish port 22 or start an SSH server. Publishing port 22 still
requires an explicit `docker run -p ...:22`, as done by the runtime smoke test.

So this looks like an opt-in image mode that may be used by some workflow, not
something active during normal MegaLinter runs.

## Ditch QEMU

I see no more cross-arch image building, all paths use arm runners afaik. So QEMU in build pipelines is no longer needed - it adds some
build time though.
