# Dovecot 2.4 for Amazon Linux 2023 (AL2023)

AL2023 ships Dovecot 2.3.20. The Dovecot project doesn't publish RPMs for AL2023, but publishes 2.4 RPMs for RHEL 9 (x86_64 only). This rebuilds their source RPMs on AL2023, for both x86_64 and aarch64. That means you can get the latest Dovecot release with its features and bug fixes and install it on any of the EC2 instances including the lower cost ARM-based Graviton hosts.

This is a stop gap project; use official AWS or [Dovecot repo](https://dovecot.org/download) packages when they become available.

## Install

Uninstall AL2023's `dovecot` and `dovecot-pigeonhole` first if you have them installed - this repo's `dovecot-sieve` conflicts with `dovecot-pigeonhole`, and dnf refuses the transaction otherwise. Also note that Dovecot 2.4 won't read a 2.3 config; see the [2.3-to-2.4 upgrade guide](https://doc.dovecot.org/latest/installation/upgrade/2.3-to-2.4.html).

These packages work on both `x86_64` and `aarch64` hosts. `dovecot-flatcurve` needs Xapian, which AL2023 ships only through the Amazon SPAL repository - skip the `spal-release` install below if you don't need `dovecot-flatcurve`:

```sh
dnf install spal-release
curl -fsSLo /etc/yum.repos.d/dovecot-2.4-al2023.repo https://yasharf.github.io/dovecot.2.4.ALinux2023/dovecot-2.4-al2023.repo
dnf install dovecot dovecot-imapd dovecot-lmtpd dovecot-sieve dovecot-managesieved dovecot-flatcurve
```

The packages are unsigned, so the repository sets `gpgcheck=0`.

New versions are likely to show up here within a day of an official RHEL release from the Dovecot team with the Github Action workflow in this repo. `dnf upgrade` picks them up when they do.

Every published build stays published. `dnf list --showduplicates dovecot` shows what's available, and you can install a specific version by name, e.g. `dnf install dovecot-2:2.4.4-5`.


## How it works

GitHub Actions handles the whole process, chained end-to-end:

- `watch.yml` checks daily for a new Dovecot RHEL release not yet published here.
- `build.yml` rebuilds it for AL2023, `x86_64` and `aarch64`.
- `verify.yml` installs the RPMs in an AL2023 container and runs IMAP/LMTP/Sieve checks against them.
- `publish.yml` publishes the RPMs as the `dnf` repository above.

### Build

[`build/build.sh`](build/build.sh) is the whole build, and runs in a docker container:

```sh
docker run --rm -v "$PWD:/w" -w /w public.ecr.aws/amazonlinux/amazonlinux:2023 ./build/build.sh 2.4.4 5
```

RPMs land in `out/RPMS`.

### Verify

[`verify/run.sh`](verify/run.sh) installs the built RPMs on a clean AL2023 host and starts Dovecot for `verify.yml` to test.

### Changes to RHEL Spec

The Dovecot sources are not touched, and the sieve spec is unmodified. Two things needed changing for AL2023:

- **`build/mariadb-devel-stub.spec`** - the spec has `BuildRequires: mariadb-devel`, which AL2023 has no package for. `mariadb-connector-c-devel` ships the same headers, so the stub provides the name and the spec stays unedited.
- **`--without-libunwind`** - three `sed` lines against the core spec. AL2023 only has libunwind 1.4.0, which cannot unwind here, and `libunwind.so` exports a `backtrace` symbol that shadows glibc's working one, so linking it breaks both of Dovecot's backtrace paths and `make check` dies in `test-backtrace`. libunwind is used by `src/lib/backtrace-string.c` and nothing else, for crash backtraces only. Built without it, the full `make check` passes.

## License

[LICENSE](LICENSE) covers this repository's own content - the build scripts, spec stub, verify harness, and workflows - under the MIT license, the same one Dovecot itself uses for part of its tree. It does not cover Dovecot: no Dovecot source is vendored here, and the RPMs this repo builds and publishes are Dovecot's own unmodified software (aside from the libunwind change above), carrying Dovecot's own `COPYING`, `COPYING.MIT`, and `COPYING.LGPL` inside each package as built by their spec.
