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

`dovecot-flatcurve` needs Xapian, which is in the Amazon SPAL repository:
`dnf install spal-release`. There is no `dnf` repository behind these RPMs, so
name every package you want in one `dnf install` — `dnf` can only resolve the
dependencies between them from the files you give it.
