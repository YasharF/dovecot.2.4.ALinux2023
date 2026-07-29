# Dovecot 2.4 for Amazon Linux 2023

AL2023 ships Dovecot 2.3.20. The Dovecot project publishes 2.4 RPMs for RHEL 9,
x86_64 only. This rebuilds their source RPMs on AL2023, for x86_64 and aarch64.

Temporary — use official AWS or Dovecot packages when they exist.

## Build

```sh
docker run --rm -v "$PWD:/w" -w /w public.ecr.aws/amazonlinux/amazonlinux:2023 \
  ./build/build.sh 2.4.4 5
```

RPMs land in `out/RPMS`. The same script runs directly on an AL2023 host as root.

[`build/build.sh`](build/build.sh) is the whole build. Two things in it are not
stock:

- **`build/mariadb-devel-stub.spec`** — the spec has `BuildRequires:
  mariadb-devel`, which AL2023 has no package for. `mariadb-connector-c-devel`
  ships the same headers, so the stub provides the name and the spec stays
  unedited.
- **`--without-libunwind`** — three `sed` lines against the core spec. AL2023
  only has libunwind 1.4.0, which cannot unwind here, and `libunwind.so` exports
  a `backtrace` symbol that shadows glibc's working one — so linking it breaks
  both of Dovecot's backtrace paths and `make check` dies in `test-backtrace`.
  libunwind is used by `src/lib/backtrace-string.c` and nothing else, for crash
  backtraces only. Built without it, the full `make check` passes.

The Dovecot sources are not touched, and the sieve spec is unmodified.

## Install

These are published as a `dnf` repository, for `x86_64` and `aarch64`. `dovecot-flatcurve` needs Xapian, which is in the Amazon SPAL repository, so enable that too:

```sh
dnf install spal-release
curl -fsSLo /etc/yum.repos.d/dovecot-2.4-al2023.repo \
  https://yasharf.github.io/dovecot.2.4.ALinux2023/dovecot-2.4-al2023.repo
dnf install dovecot dovecot-imapd dovecot-lmtpd dovecot-sieve \
  dovecot-managesieved dovecot-flatcurve
```

The packages are unsigned, so the repository sets `gpgcheck=0`.

A host carrying the distribution's `dovecot` and `dovecot-pigeonhole` removes them first — `dovecot-sieve` conflicts with `dovecot-pigeonhole`, and that transaction is refused otherwise.

Every published build stays published. `dnf list --showduplicates dovecot` shows what is there, and an earlier one can be installed by name — `dnf install dovecot-2:2.4.4-5` — if a newer build turns out to be worse.
