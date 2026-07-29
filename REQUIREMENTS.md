# Dovecot 2.4 for Amazon Linux 2023 — requirements and plan

Rebuild Dovecot CE 2.4 (core + Pigeonhole/Sieve, including the in-core Xapian FTS backend) as RPMs for Amazon Linux 2023, `aarch64` and `x86_64`.

Findings below were measured on AL2023, on an `aarch64` host and on GitHub-hosted runners of both architectures, 2026-07-28/29. Anything not measured is marked as such.

## 1. Why the project exists

- AL2023 ships Dovecot 2.3.20.
- The Dovecot project has made 2.3 security-fix-only since 2025-05-12; non-security bugs are closed with "reproduce it on 2.4".
- There is no supported and maintained Xapian FTS plugin for AL2023 Dovecot 2.3. It was not packaged for AL2023, and has a defect fixed only in Dovecot 2.4.2+. The standalone Xapian FTS repo is deprecated in favour of its inclusion in Dovecot 2.4.
- The Dovecot project publishes 2.4 RPMs for RHEL 9/10 for **x86_64**. AL2023 needs **aarch64** builds for Graviton instances in addition to x86_64 builds.

## 2. Scope

In scope:

- RPMs of Dovecot 2.4.x core and Pigeonhole/Sieve for AL2023, both architectures.
- The full subpackage set the Dovecot project ships.
- An automated rebuild from the Dovecot project's source RPMs, with no changes to the sources and one documented change to the core spec (§5.1).
- Verification that the packages install and serve IMAP on a clean AL2023 system of each architecture.

Out of scope:

- Mail server configuration, and migrating any deployment from 2.3 to 2.4. Converting a configuration, and getting a host from the distribution's packages onto these, is the consumer's work.
- Installation tooling. Consumers fetch the RPMs and install them however they already install RPMs.
- Patching Dovecot. The project builds the Dovecot project's RPM source as is.
- Changing the spec files, beyond the one change in §5.1. Anything else AL2023 needs is handled in the build environment. The bar for a second change is the one the first cleared: a measured defect on AL2023 that the build environment cannot address, in something the packages do not need to do their job.
- Backporting to Amazon Linux 2, or forward-porting to whatever succeeds AL2023.
- Anything Dovecot Pro.

The governing constraint is that this project owns no more than the rebuild.

### Lifetime

This project is temporary. It exists because there are currently no official AL2023-compatible RPMs for Dovecot 2.4. Plan to switch to the official AWS or Dovecot package when one exists.

## 3. Findings the plan rests on

**Distribution has 2.3 only.** `dovecot`, `dovecot-devel`, `dovecot-pigeonhole`, `dovecot-mysql`, `dovecot-pgsql` are all `1:2.3.20-1.amzn2023.0.3`. SPAL (`dnf install spal-release`) adds no Dovecot.

**Dovecot project RPMs are x86_64-only.** `repo.dovecot.org/ce-2.4-latest/rhel/{9,10}/RPMS/x86_64/` carries a full package set; the sibling `aarch64/` path is HTTP 404 on both.

**The Dovecot project publishes its source RPMs.** `rhel/9/SRPMS/` carries `dovecot-2.4.4-5.src.rpm` and `dovecot-sieve-2.4.4-5.src.rpm` — the specs it builds its own x86_64 packages from.

**2.4.4 rebuilds on AL2023 on both architectures.** The Dovecot project's full option set, `make check` passing, 34 RPMs per architecture including `dovecot-flatcurve` linked against SPAL's `libxapian`.

**AL2023's libunwind is too old for Dovecot 2.4, and linking it is worse than not.** `libunwind` 1.4.0 is the only version AL2023 offers. It cannot unwind here, and because `libunwind.so.8` exports its own `backtrace` symbol it shadows glibc's working one — so Dovecot's "fall back to libc" path is not a fallback at all. Both backtrace paths fail and `make check` dies in `test-backtrace`. This is the one thing that made a spec change unavoidable; see §5.1.

**`make check` fails if the build runs as root.** `src/lib/test-buffer-istream.c` chmods a file to `000` and asserts that reading it fails. Root ignores that. `rpmbuild` therefore runs as an unprivileged user; only `dnf` runs as root.

**The core spec assumes an EL build root.** It carries no `BuildRequires: gcc-c++`, but `src/plugins/fts-flatcurve/fts-backend-flatcurve-xapian.cc` is C++. On EL that comes from the build root before any `BuildRequires` is read; the AL2023 container image supplies almost none of that baseline, so the build environment installs it. The sieve spec does declare `gcc-c++`.

**`mariadb-devel` is a package-name gap, not a missing library.** On EL9 that package ships the MariaDB client headers. AL2023 ships the same content as `mariadb-connector-c-devel`: `/usr/bin/mysql_config`, `/usr/include/mysql/mysql.h`, and `pkgconfig(libmariadb)`. Dovecot's `m4/want_mysql.m4` looks for `pkg-config mysqlclient` and falls back to `pkg-config libmariadb`, which AL2023 satisfies, so `--with-mysql` compiles as is. Only the literal `BuildRequires` name fails to resolve.

**Two AL2023 packages conflict with names the build might ask for.** `curl` conflicts with the `curl-minimal` the image ships, and `coreutils` with `coreutils-single`. Neither is needed; asking for them by name turns a satisfied requirement into a broken transaction.

**`make check` needs more than a 2 vCPU runner on aarch64.** `test-http-payload` has a hard 60-second request deadline and timed out on the 2 vCPU runners a private repository gets. It passed on a dedicated 1 vCPU AL2023 host and on the 4 vCPU runners a public repository gets, so it is contention, not an architecture limit. Fedora's spec skips `%check` on aarch64 with the comment "some aarch64 tests timeout"; this project does not need to.

**Build hosts need several GiB free.** A first attempt with static libraries enabled filled an 8 GiB root filesystem mid-build. RPM builds with debuginfo need more again.

**The 2.3 FTS plugin is EOL.** `slusarz/dovecot-fts-flatcurve`: last release v1.0.5 (2024-09-25), last push 2025-05-09, explicit EOL notice. Known 2.3 issue: fails "if multiple mailbox directories require updates within a single session", fixed in 2.4.2+.

**fts-flatcurve and Maildir take two locks in opposite orders, and concurrent clients deadlock.** Measured on both architectures, roughly half of Verify jobs, with `fts_autoindex = yes` and four imaptest clients. `EXPUNGE` makes the imap process update the FTS index from inside `maildir_sync_index`, which already holds the `dovecot-uidlist` dotlock, and it then sleeps in `fts_flatcurve_xapian_write_db_get_do`'s retry loop waiting for Xapian's `flintlock` (`fts-backend-flatcurve-xapian.cc:423`). Meanwhile `indexer-worker`, holding the Xapian write DB, blocks in `maildir_uidlist_lock_timeout` waiting for that same dotlock. Neither side gives way and nothing is logged, because waiting is not an error to either. Every other client then piles up behind the uidlist lock and the server stops making progress. It is bounded rather than permanent: `FLATCURVE_DBW_LOCK_RETRY_SECS` is 1 and `FLATCURVE_DBW_LOCK_RETRY_MAX` is 60, so flatcurve gives up after 60 seconds with `DB (RW, ...) was locked for over 60 seconds`, which matches the 50-92 second stalls measured. With `fts_search_read_fallback = no` that surfaces as a failed search rather than a slow one.

**This is not a dependency-version problem.** AL2023's SPAL carries Xapian **1.4.20**; EL9, which the Dovecot project builds its own `dovecot-flatcurve` against, carries **1.4.18** — so this build links the *newer* library, and `m4/want_flatcurve.m4` asks only for `xapian-core >= 1.4` with no upper bound. Neither stuck process is inside Xapian: both wait in Dovecot's own `dotlock_wait` and in flatcurve's retry loop, with Xapian appearing only as the component correctly refusing a second writer, which is its design in every 1.4.x. The lock *ordering* is entirely Dovecot's. Any Dovecot 2.4.4 with flatcurve on Maildir and concurrent access should reproduce it. It is upstream behaviour, unchanged here, and out of this project's scope to fix; it is recorded because it shapes how the verification is configured.

**A host with the distribution's packages installed needs a hand.** AL2023 sets `Epoch: 1` and the Dovecot project sets `Epoch: 2`, so the core package orders as an upgrade. But the distribution calls Sieve `dovecot-pigeonhole`, the Dovecot project calls it `dovecot-sieve` and carries `Conflicts: dovecot-pigeonhole` rather than `Obsoletes:`, so that transaction is refused. Adding the `Obsoletes:` would be a spec change and a migration path this project does not own: a consumer coming off the distribution's packages removes them first. This is upstream packaging behaviour, unchanged here.

**Security fix currency.** AL2023's SRPM applies CVE-2024-23184, CVE-2024-23185, CVE-2026-27856/27857/27858. 2.4.4 NEWS lists CVE-2026-27851, -33603, -40020, -42006, the last noting the CVE-2026-27857 fix was incomplete. Re-check both sides before quoting.

## 4. Requirements

### 4.1 Functional

- **R1** — Build RPMs of Dovecot core 2.4.x and Pigeonhole/Sieve 2.4.x for AL2023.
- **R2** — Both `aarch64` and `x86_64`, from one run. A build missing an architecture is not a build.
- **R3** — Include `dovecot-flatcurve`, built against a Xapian available to AL2023 hosts.
- **R4** — Package names, layout, split and EVR are the Dovecot project's, unchanged, and the full subpackage set its spec produces is built. Nothing is trimmed, renamed or re-versioned.
- **R5** — The build modifies no Dovecot source. The core spec carries exactly one change, `--without-libunwind` (§5.1); the sieve spec carries none. Everything else AL2023 needs is handled in the build environment.
- **R6** — The build is one script that runs the same way in CI and on a clean AL2023 host.

### 4.2 Platform and dependencies

- **R7** — Target AL2023, built against its own toolchain. Not expected to run on RHEL, Fedora or AL2.
- **R8** — Runtime dependencies come from `amazonlinux`, except Xapian, which AL2023 ships only in SPAL and which `dovecot-flatcurve` links. Enabling SPAL is noted as a prerequisite. What SPAL is and whether to use it is the consumer's call, not this project's to explain.
- **R9** — Language processing follows the Dovecot project's EL9 build: `libstemmer` and `libicu` in, `libexttextcat` out.

### 4.3 Verification

`make check` covers Dovecot's own code. It never opens a TLS session and never indexes anything in Xapian — and those run against AL2023's OpenSSL and Xapian, which no other Dovecot build uses. That gap is what the rest of this section is for.

- **R10** — `make check` runs during the build of both packages on each architecture; a failure fails the build.
- **R11** — Every built RPM installs on a clean AL2023 system of each architecture, with only `amazonlinux` and SPAL enabled, and Dovecot then starts and serves IMAP. Installing the whole set in one transaction is the dependency-resolution check: it resolves for real rather than inspecting metadata.
- **R12** — The IMAP client is the Dovecot project's own [imaptest](https://github.com/dovecot/imaptest), not one written here. It runs over TLS, so the session exercises AL2023's OpenSSL, and against a configuration with `fts_flatcurve` enabled, so its `BODY` and `TEXT` searches exercise AL2023's Xapian. Three things make that exercise into a check rather than a formality, and none is a default: `search=` on the command line, because imaptest's `SEARCH` state has a default probability of **0** and without it not one SEARCH is ever sent — it runs as a second, single-client invocation, because combining searches with concurrent clients hits the deadlock in §3; `fts_search_read_fallback = no`, without which a failed FTS lookup silently falls back to a non-indexed search and returns the right answer anyway, so a broken Xapian would pass; and an explicit `ssl_min_protocol`/`ssl_cipher_list` with `ssl = required`, so OpenSSL parses and applies a restrictive list instead of its defaults.
- **R13** — TLS SNI selects between two certificates. `local_name` serves a second self-signed cert to clients that ask for it by name, and `openssl s_client -servername` confirms which one came back. Both certs are generated by `verify/run.sh`, so this needs nothing provisioned.
- **R14** — Verification runs from the built RPMs, independently of the build, so it can be re-run against an existing build without repeating it.
- **R15** — LMTP delivery is exercised by imaptest's profile mode, the one mode in which it speaks LMTP. `verify/imaptest-profile.conf` describes one user and one IDLEing IMAP client; imaptest delivers to that user's INBOX over LMTP and drives the IMAP session reacting to the delivery. The config is the whole of this project's contribution — imaptest does the driving.
- **R16** — Pigeonhole's `fileinto` action is exercised against a real mailbox by [sieve-test](https://doc.dovecot.org/main/core/man/sieve-test.1.html), the Pigeonhole project's own script tester: it runs `verify/sieve-test.sieve` against `verify/sieve-test-mail.eml` with `-e` (actually execute, not just report), and `doveadm search` confirms the message landed in the non-`INBOX` mailbox the rule names. imaptest never runs a Sieve script in any mode — its profile mode reaches a non-INBOX folder through plus-addressing, not Sieve — so this is the only thing that covers the action.

- **R17** — ManageSieve is exercised as a protocol, not just started: `openssl s_client -starttls sieve` opens a real STARTTLS session on 4190, authenticates as the test user, uploads a script with `PUTSCRIPT` and lists it back with `LISTSCRIPTS`. `ssl = required` means the session has to negotiate STARTTLS before it can authenticate at all.

Not covered: the packaged systemd unit, since verification runs `dovecot -F` directly.

### 4.4 Distribution

- **R18** — Both architectures' RPMs come from a single CI run and are downloadable from it.
- **R19** — **Not yet met.** Today the RPMs are workflow artifacts, which expire and are awkward to consume. A durable, versioned publication — a GitHub Release per build, tagged with the Dovecot version and upstream SRPM release, carrying every RPM for both architectures — is the intended end state. Until that exists, this project produces builds rather than releases.

## 5. Design

### 5.1 Source of truth

Each build uses the Dovecot project's EL9 `dovecot-<ver>.src.rpm` and `dovecot-sieve-<ver>.src.rpm`, rather than a spec written here or Fedora's — Fedora's needs its version conditionals audited every release. If an EL9 source RPM ever stops appearing for a new Dovecot release, the project stops rather than growing a spec of its own.

The Dovecot sources are never touched. The sieve spec is built with `rpmbuild --rebuild`, unmodified. The core spec carries one change; everything else AL2023 needs is handled in the build environment.

**The one spec change: `--with-libunwind` → `--without-libunwind`**, along with the `BuildRequires: libunwind-devel` and `Requires: libunwind` that go with it. Three `sed` lines in `build/build.sh`, followed by a `grep` that fails the build if they did not apply.

Why it is necessary, measured on AL2023:

- AL2023 ships `libunwind` **1.4.0** (2020) and nothing newer, in `amazonlinux` or SPAL. EL9 has 1.6.x and Fedora 1.8.x, which is why the Dovecot project's own EL9 packages do not hit this.
- libunwind 1.4.0 cannot walk the stack here. Dovecot's libunwind path fails with `No symbols found (process chrooted?)`.
- Dovecot is written to fall back to glibc when that happens — *"libc's own method is likely better"*, per the comment in `backtrace-string.c`. On AL2023 the fallback does not happen: `libunwind.so.8` exports its own `backtrace` symbol, which shadows glibc's. `gcc bt.c` gives 4 frames; `gcc bt.c -lunwind -lunwind-generic` gives 1, from `libunwind.so.8(backtrace+0x4e)`.
- Both of Dovecot's backtrace implementations therefore end up inside the same broken 1.4.0, `backtrace_get()` returns -1, and `src/lib/test-backtrace.c` calls `strstr()` on the `NULL` it was left with and segfaults. That is what fails `make check`.
- Built `--without-libunwind`, the full `make check` passes and Dovecot uses glibc's `backtrace()`, which works on AL2023.

Why it is safe: libunwind is used by exactly one file in the Dovecot tree, `src/lib/backtrace-string.c`, and only to render crash backtraces. No mail, storage, authentication or index path touches it. This changes which implementation produces a backtrace after a crash — and on AL2023 it leaves the one that works. It is not a workaround for a missing libunwind feature: Dovecot calls only `unw_getcontext`, `unw_init_local`, `unw_step`, `unw_get_proc_info` and `unw_get_proc_name`, all of which exist in 1.4.

Nothing in the Pigeonhole tree references libunwind; its spec's `BuildRequires: libunwind-devel` is vestigial, and it links against whatever `dovecot-config` records.

### 5.2 Build environment

`build/build.sh`, run inside `public.ecr.aws/amazonlinux/amazonlinux:2023` or directly on an AL2023 host. Core first — `dovecot-sieve` build-requires the `dovecot-devel` it produces, and the whole core set has to be installed for that to resolve, because `dovecot` needs `libdovecot-lua.so.0` and `dovecot-devel` needs `libdovecot-gssapi.so.0`. Per-architecture builds run natively, not emulated.

Two things the environment supplies that the spec assumes:

- **An EL build root baseline** — `gcc`, `gcc-c++`, `make`, `patch` and the rest, which the container image does not have.
- **`build/mariadb-devel-stub.spec`** — a package that `Provides: mariadb-devel` and `Requires: mariadb-connector-c-devel`. This keeps the spec unedited and leaves dependency checking on for every other `BuildRequires`, which `rpmbuild --nodeps` would not. Build environment only; never published.

`rpmbuild` runs as an unprivileged `builder` user; `dnf` runs as root.

### 5.3 Automation

Two workflows:

- **Build** — manually triggered with a Dovecot version and upstream SRPM release. Runs `build/build.sh` in the AL2023 container on `ubuntu-24.04` and `ubuntu-24.04-arm`, and uploads each architecture's RPMs as an artifact. On `make check` failure it prints every `test-suite.log`, which is the only place automake names the failing subtest.
- **Verify** — triggered when Build completes, or manually against any past Build's run id. Installs that run's RPMs on a clean AL2023 container, starts Dovecot, points the `dovecot/imaptest` container at it over TLS twice — once for the IMAP stress run, once in profile mode for LMTP — and runs `sieve-test`, `doveadm` and `openssl s_client` against the running install.

They are separate so verification can be re-run without repeating a ~25-minute rebuild.

The runners must be a public repository's 4 vCPU ones; see §3 on `test-http-payload`.

### 5.4 Publishing

Not built yet. Today the output is a workflow artifact per architecture.

The intended end state is a GitHub Release per build carrying every RPM for both architectures. No `dnf` repository, no hosting to run: for a project with this lifetime the metadata, the domain and the bucket cost more than they return.

Consumers download what they want and install it however they install RPMs. The one thing worth documenting is that without a `dnf` repository behind them, the dependencies *between* these packages can only be satisfied from the files named in the same transaction — and that `dnf upgrade` will not find a newer build on its own.

If this ever needs to be a real `dnf` repository, the RPMs are the same artifacts: `createrepo_c` over them plus somewhere to serve them, with no rebuild.

### 5.5 Versioning

The package `Epoch`, `Version` and `Release` are the Dovecot project's, unchanged — not even a distribution tag, which would be a spec change and would break the sieve spec's hardcoded EVR pins on core. Two builds of the same upstream release are therefore indistinguishable by EVR, which is correct: they are the same packages. Whatever identifies a build has to live outside the RPMs — today the workflow run, later the release tag.

## 6. Verification plan

In the build, on each architecture:

1. `make check` for core and for sieve. A failure fails the build.

On a clean AL2023 system, per architecture, from the built RPMs:

2. All 34 RPMs install in one transaction with only `amazonlinux` and SPAL enabled.
3. `doveconf -n` parses a minimal 2.4 configuration and Dovecot starts.
4. imaptest logs in over TLS with four concurrent clients and drives `LIST`, `STATUS`, `SELECT`, `FETCH`, `STORE`, `DELETE`, `EXPUNGE` and `APPEND` with state tracking, quitting non-zero on the first mismatch. `SEARCH` stays at its default probability of 0 here, so nothing writes the Xapian index while the four clients run.
5. imaptest runs again with a single client and `search=50`, which is what exercises Xapian at all. Its `BODY` and `TEXT` searches route through `fts_flatcurve`; because it appends from a known mbox it tracks the body words it sent, so a search that fails to return a message it should is reported as `SEARCH result missing`. Single-client because concurrency plus FTS writes is the combination that deadlocks (§3).
6. imaptest in profile mode delivers to the test user's INBOX over LMTP and drives the IMAP session that reacts to each delivery. A global `sieve_before` script files a `:copy` of every delivery into a second mailbox, so `doveadm search` finding it there proves Sieve ran inside the delivery path rather than only under `sieve-test`.
7. `sieve-test -e` compiles and actually executes a `fileinto` rule against the test user's real mailbox; `doveadm search` confirms the message landed there rather than in `INBOX`.
8. `openssl s_client`, with and without `-servername`, gets back the two different certificates `local_name` selects between.
9. `openssl s_client -starttls sieve` authenticates over ManageSieve, uploads a script and lists it back.

Known gap: imaptest can prove a false negative from FTS but not a false positive — it does not index the full message text itself, so a backend returning *extra* matches would go unnoticed. The other direction is covered: with `fts_search_read_fallback = no` a failed lookup is an error rather than a silent non-indexed search, so a broken Xapian fails the run instead of quietly returning the right answer.

## 7. Status

1. **Feasibility** — done.
2. **Rebuild** — done. Both architectures, `make check` passing, 34 RPMs each.
3. **Verification** — done. Install, concurrent imaptest over TLS, single-client imaptest SEARCH through Xapian, imaptest LMTP profile mode with Sieve on the delivery path, sieve-test, SNI certificate selection and ManageSieve all passing on both architectures.
4. **Automation** — done. Build and Verify workflows.
5. **Publication** — not started. See R19.
6. **Dovecot release tracking** — not started. No scheduled check for new upstream releases, and no written procedure for taking one from rebuild to publication.

## 8. Consumer note

Dovecot 2.4 will not read a 2.3 configuration, and nothing converts one automatically. The Dovecot project's [2.3 → 2.4 upgrade documentation](https://doc.dovecot.org/latest/installation/upgrade/2.3-to-2.4.html) is the reference and the only one this project points at.

A host carrying the distribution's `dovecot` and `dovecot-pigeonhole` removes them before installing these packages; see §3 for why that transaction is refused otherwise.

## 9. References

- Dovecot releases: `https://dovecot.org/releases/2.4/`, `https://pigeonhole.dovecot.org/releases/2.4/`
- Dovecot project RPMs and SRPMs: `https://repo.dovecot.org/`
- imaptest: `https://github.com/dovecot/imaptest`
- 2.3 → 2.4 upgrade: `https://doc.dovecot.org/latest/installation/upgrade/2.3-to-2.4.html`
- `fts-flatcurve` EOL notice: `https://slusarz.github.io/dovecot-fts-flatcurve/eol.html`
- Fedora packaging: `https://src.fedoraproject.org/rpms/dovecot`
- SPAL: `https://docs.aws.amazon.com/linux/al2023/ug/epel.html`
