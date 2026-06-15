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

### 1. Real runtime blockers

These still matter for non-root execution and should be treated as follow-up work.

#### PHP Composer tool path

Still present:

- `ENV PATH="/root/.composer/vendor/bin:${PATH}"`

Relevant sources:

- `megalinter/descriptors/php.megalinter-descriptor.yml`
- generated PHP Dockerfiles

Observed effect in non-root image check:

- `phpcs`
- `phpstan`
- `psalm`
- `phplint`
- `php-cs-fixer`

were not found.

This is the clearest next target after Rust and .NET.

#### SSH support path

Still present:

- `mkdir /root/docker_ssh`

Source:

- `.automation/build.py`

This is likely to break SSH-related features under non-root.

### 2. Harmless build-time or cleanup leftovers

These are ugly but are not the main runtime problem.

- `/root/.cache/...`
- `/root/.npm/_cacache`
- `/root/.wget-hsts`
- `/root/.perl-cpm`
- `--mount=type=cache,target=/root/.cache/uv`
- `rm -rf /root/.cache`

These can be cleaned later, but they are not the primary blockers for non-root runtime.

### 3. Cases worth reviewing, but not the first priority

#### npm

Your other project uses:

- `npm config set prefix /usr/local`

That is sensible for true global npm installs.

But this repo's main generated npm install path is different:

- `.automation/build.py` installs npm packages into `/node-deps/node_modules/.bin`
- that is a local install path, not the global npm prefix

So:

- changing npm prefix is useful for real global npm installs
- but it does not solve the main `/node-deps` install path by itself

Observed non-root check still showed some npm-based CLIs missing, but they were not yet categorized into:

- actually broken install path
- not present in the built image
- simply not covered by the tested image/flavor

This should be audited after PHP and SSH.

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
2. PHP Composer tools are very likely the next real runtime blocker.
3. `/root/docker_ssh` is likely another real blocker for SSH mode.
4. Many remaining `/root/...` references are just cache or cleanup paths and are lower priority.
5. npm needs a narrower audit:
   - global npm installs may benefit from `/usr/local` prefix
   - local `/node-deps` installs are a separate mechanism

## Suggested Next Tasks

1. Move PHP Composer-installed tools out of `/root/.composer/vendor/bin` into a neutral runtime path.
2. Replace `/root/docker_ssh` with a non-root-safe location.
3. Re-check the non-root command availability inside the rebuilt image.
4. Only then continue with npm-specific cleanup or global prefix changes.

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
