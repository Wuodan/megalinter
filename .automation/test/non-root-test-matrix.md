# Runtime Coverage Tasks

## Goal

Add small end-to-end checks that actually cover runtime/install behavior before further root vs non-root work.

Current `mega-linter-runner` npm tests are useful as broad smoke tests, but they do not prove:

- install payload goes where expected
- targeted tools are actually available at runtime
- selected linters are actually runnable end-to-end
- SSH startup works end-to-end

## Suggested Tasks

### 1. Build-Time Image Inspection

Purpose: catch install payload regressions.

Suggested assertions:

- assert expected install locations exist
- assert known unwanted leftover locations do not exist
- keep the assertions focused on the tools we touched

Possible command shape:

```bash
docker run --rm --entrypoint bash megalinter-local:test -lc '
test ! -d /root/.cargo &&
test ! -d /root/.composer/vendor &&
test ! -d /root/.dotnet/tools &&
test ! -d /root/.local/share/sf
'
```

### 2. Targeted Command Availability

Purpose: catch PATH/install-location breakage without running full lint fixtures.

Suggested commands to assert with `command -v`:

- `cargo`
- `rustfmt`
- `csharpier`
- `roslynator`
- `php-cs-fixer`
- `phpstan`
- `psalm`
- `phplint`
- `sf`

Possible command shape:

```bash
docker run --rm --entrypoint bash --user 1000:1000 megalinter-local:test -lc '
for cmd in cargo rustfmt csharpier roslynator php-cs-fixer phpstan psalm phplint sf; do
  command -v "$cmd" >/dev/null || exit 1
done
'
```

### 3. Targeted Linter Smoke

Purpose: prove the tool is not only on `PATH`, but actually runnable through MegaLinter.

Suggested minimal fixture coverage:

- Rust: `RUST_CLIPPY`
- C#: `CSHARP_CSHARPIER`
- PHP: `PHP_PHP_CS_FIXER`
- Salesforce: one `code-analyzer-*` linter

Suggested assertion style:

- run a tiny targeted fixture
- assert the expected success/failure status
- assert an expected report/log artifact exists

### 4. SSH End-to-End

Purpose: prove `entrypoint.sh` SSH behavior actually works.

Suggested assertion style:

- start container with `MEGALINTER_SSH=true`
- mount a test public key into the expected SSH volume folder
- wait for port `2222`
- `ssh` into the container
- run `id`
- assert success

### 5. Keep One Broad Runner Smoke

Purpose: preserve coverage that the runner still launches the image at all.

Suggested scope:

- keep one existing `mega-linter-runner` integration smoke
- do not treat it as proof that runtime behavior is covered

## Later Dimension

After baseline runtime coverage exists, run relevant checks in both modes:

1. default/root container mode
2. mapped-user/non-root mode on POSIX hosts

## Recommended Minimal Set

If this needs to stay small, the highest-value baseline set is:

1. build-time image inspection
2. targeted command availability
3. PHP targeted smoke
4. Salesforce targeted smoke
5. SSH end-to-end
