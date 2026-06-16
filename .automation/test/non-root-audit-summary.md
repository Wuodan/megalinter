# Non-Root Audit Summary

## Current Goal

Make MegaLinter work correctly when the container runs as the host user on Linux, instead of as `root`.

The current runner-side approach is:

- `mega-linter-runner` passes `docker run --user <uid>:<gid>` on POSIX hosts
- it sets `HOME=/tmp/megalinter-home`
- `entrypoint.sh` creates `$HOME` early so startup code has a writable home

This part appears to work for the tested local runner path.

## What Was Already Fixed

### Rust

Rust was previously installed into `/root/.cargo`, which is not accessible to non-root users because `/root` itself is `0700`.

This was changed to:

- `RUSTUP_HOME=/usr/local/rustup`
- `CARGO_HOME=/usr/local/cargo`
- `PATH=/usr/local/cargo/bin:${PATH}`
- symlinks for Rust tool binaries into `/usr/local/bin`

Source changes:

- `.automation/build.py`
- `Dockerfile`
- `flavors/rust/Dockerfile`
- `flavors/cupcake/Dockerfile`
- `linters/rust_clippy/Dockerfile`

### .NET tools

.NET tools were previously installed into `/root/.dotnet/tools`, which has the same non-root problem.

This was changed to:

- install tools with `--tool-path /usr/local/dotnet-tools`
- add `/usr/local/dotnet-tools` to `PATH`

Source changes:

- descriptor files:
  - `megalinter/descriptors/csharp.megalinter-descriptor.yml`
  - `megalinter/descriptors/vbdotnet.megalinter-descriptor.yml`
  - `megalinter/descriptors/repository.megalinter-descriptor.yml`
  - `megalinter/descriptors/sql.megalinter-descriptor.yml`
- checked-in Dockerfiles for related flavors/linters

## Remaining `/root/...` Categories

### 1. Fixed source definitions

These were real first-party `/root/...` definitions and were migrated out of `/root`.

- PHP Composer tool path:
  - `megalinter/descriptors/php.megalinter-descriptor.yml`
  - moved from `/root/.composer/vendor/bin` to `/usr/local/composer/vendor/bin`
- SSH support path:
  - `.automation/build.py`
  - `entrypoint.sh`
  - moved from `/root/docker_ssh` to `/tmp/docker_ssh`
  - `entrypoint.sh` no longer hard-codes `/root/.ssh/authorized_keys`
- npm global prefix:
  - `.automation/build.py`
  - now emits `npm config set prefix /usr/local`
- cache paths:
  - `Dockerfile`
  - `.automation/build.py`
  - `megalinter/descriptors/scala.megalinter-descriptor.yml`
  - migrated selected first-party `/root/.cache...` paths to `/tmp/.cache...`
  - this now looks debatable rather than clearly required; build-time cache mounts may reasonably stay under `/root`

### 2. Remaining first-party source definitions

These are still present in non-generated sources, but they are build-time cleanup only.

- `megalinter/descriptors/salesforce.megalinter-descriptor.yml`
  - multiple `rm -rf /root/.npm/_cacache`
  - npm cleanup-only
- `megalinter/descriptors/perl.megalinter-descriptor.yml`
  - `rm -rf /root/.perl-cpm`
  - cleanup-only
- `megalinter/descriptors/dart.megalinter-descriptor.yml`
  - `rm "/root/.wget-hsts"`
  - cleanup-only

These do not look like non-root runtime blockers.

### 2a. Build-time cache paths

These should be treated separately from runtime path problems.

- `--mount=type=cache,target=/root/.cache/uv`
- similar cache-mount patterns

Current conclusion:

- these are build-time cache locations, not runtime install paths
- they do not appear to be the same class of non-root problem as `/root/.composer`, `/root/docker_ssh`, or `/root/.dotnet/tools`
- unless they are shown to cause an actual build/runtime issue, they are probably better left unchanged

### 3. Generated residue

These are checked-in generated files that still contain `/root/...` and should not be patched directly.

- generated Dockerfiles under `flavors/` and `linters/`
- generated docs under `docs/descriptors/`

Current recurring generated patterns:

- `/root/.npm/_cacache`
- `/root/.perl-cpm`
- `/root/.wget-hsts`
- some stale `/root/docker_ssh` hits if the corresponding generated Dockerfiles were not refreshed

If source has already been fixed but generated files still show `/root/...`, regeneration is incomplete or stale.

### 4. Third-party / captured output

Some `/root/...` hits are not first-party definitions but text emitted by tools or copied from their docs/help output.

Examples:

- `.automation/generated/linter-helps.json`
- `docs/descriptors/php_php_cs_fixer.md`
- tool help/docs mentioning defaults such as:
  - `/root/.cache/trivy`
  - `/root/.kubescape`
  - `/root/.config/helm/...`
  - `/root/.config/luacheck/...`

These should be treated separately from actual runtime path definitions.

### 5. npm-specific note

`npm config set prefix /usr/local` is now defined in source, but the main MegaLinter npm install path is still:

- `/node-deps/node_modules/.bin`

So npm prefix cleanup and `/node-deps` behavior are separate topics.

## Test Coverage Status

### What currently exists

Runner smoke tests were expanded to include:

- a `CSHARP_CSHARPIER` CLI smoke test
- a `RUST_CLIPPY` module smoke test

The Rust test originally pointed at the parent fixture directory and failed because it included both good and bad samples. That was corrected to point at:

- `.automation/test/rust/good`

### Important limitation

`Dockerfile-quick` is only enough for:

- runner changes
- `entrypoint.sh`
- Python package/descriptors copied on top of the published image

It is **not** enough to validate install-path changes like Rust/.NET, because those live in the underlying image build steps.

To validate install-path changes, a real image build from the updated Dockerfile is needed.

## Useful Conclusions From This Session

1. Rust and .NET had real non-root runtime failures and were fixed by moving installs out of `/root`.
2. PHP and SSH first-party `/root/...` definitions were also moved out of `/root`.
3. The remaining `/root/...` hits are now a mix of:
   - first-party cleanup paths still in descriptors
   - stale/generated Dockerfiles/docs
   - third-party help/default-path output
4. At this stage, the main value of further cleanup is audit clarity, not just runtime correctness.
5. npm still needs separate review for `/node-deps`, which is different from global npm prefix handling.

## Suggested Next Tasks

1. Rebuild/regenerate and verify which generated Dockerfiles/docs still contain stale `/root/...` content.
2. Consider reverting `/root/.cache -> /tmp/.cache` changes if the goal is to keep build-time cache mounts out of scope.

## Commands That Were Useful

Build local image from current sources:

```bash
export GITHUB_TOKEN="$(gh auth token)"
docker buildx build --platform linux/amd64 --load -t megalinter-local:test --secret id=GITHUB_TOKEN .
```

Then run npm-test with:

```bash
MEGALINTER_IMAGE=megalinter-local:test MEGALINTER_NO_DOCKER_PULL=true npm --prefix mega-linter-runner test &> .automation/test/npm-test.non-root.log
```

Non-root command availability check inside the built image:

```bash
docker run --rm --entrypoint bash --user 1000:1000 megalinter-local:test -lc '
printf "PATH=%s\n" "$PATH"
for cmd in cargo rustfmt csharpier roslynator TSQLLint devskim phpcs phpstan psalm phplint php-cs-fixer npmPkgJsonLint prettier v8r secretlint cspell; do
  printf "%s=%s\n" "$cmd" "$(command -v "$cmd" || true)"
done
'
```

PHP CLI help check inside the built image:

```bash
docker run --rm --entrypoint bash megalinter-local:test -lc 'php-cs-fixer list | sed -n "1,80p"'
```

This was the main check used to separate:

- fixed runtime tools
- still missing runtime tools
- likely harmless `/root` leftovers
