#!/bin/bash
# Rebuild Dovecot 2.4 core + Sieve for Amazon Linux 2023.
#
#   build/build.sh 2.4.4 5
#
# Run on AL2023 as root (a container is fine). RPMs land in ./out/RPMS.

set -eux -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
V=${1:?usage: build.sh <dovecot-version> <upstream-srpm-release>}
R=${2:?usage: build.sh <dovecot-version> <upstream-srpm-release>}
BASE=${DOVECOT_REPO_BASE:-https://repo.dovecot.org/ce-2.4-latest/rhel/9/SRPMS}
DEST=$PWD/out/RPMS
LOGS=$PWD/out/test-logs
# Not $PWD: in CI that's a bind mount of the runner's workspace, and
# src/lib/test-cpu-limit's system-CPU-time subtests have hung for hours over
# one. Building on the container's own filesystem instead. $PWD no longer
# needs to be traversable by the unprivileged builder either.
WORK=${DOVECOT_BUILD_WORK:-/var/tmp/dovecot-build}
TOP=$WORK/rpmbuild

# No curl here: AL2023 ships curl-minimal, and asking for curl conflicts with it.
dnf -y install rpm-build 'dnf-command(builddep)' spal-release \
    findutils tar gzip gcc gcc-c++ make patch util-linux

# dnf needs root, rpmbuild must not have it: make check has tests that chmod a
# file to 000 and expect reading it to fail, which it does not for root.
id builder >/dev/null 2>&1 || useradd -m builder
build() { runuser -u builder -- "$@"; }

# The work tree is inside the container, which docker removes on exit, so
# test-suite.log -- the only place automake names a failing subtest -- has to be
# copied back to $PWD first. The Build workflow prints these.
save_test_logs() {
    [ -d "$TOP/BUILD" ] || return 0
    rm -rf "$LOGS"
    mkdir -p "$LOGS"
    (cd "$TOP/BUILD" && find . -name test-suite.log \
        -exec cp --parents {} "$LOGS/" \;) || true
}
trap save_test_logs EXIT

rm -rf "$WORK"
mkdir -p "$WORK"
chown builder "$WORK"

# AL2023 has no package named mariadb-devel. mariadb-connector-c-devel ships the
# same headers, so provide the name and leave the spec's BuildRequires alone.
install -o builder "$HERE/mariadb-devel-stub.spec" "$WORK/"
build rpmbuild -bb --define "_topdir $TOP" "$WORK/mariadb-devel-stub.spec"
dnf -y install "$TOP"/RPMS/noarch/al2023-mariadb-devel-compat-*.rpm

curl -fsS --retry 5 --retry-delay 5 --retry-all-errors -o "$WORK/dovecot-$V-$R.src.rpm"       "$BASE/dovecot-$V-$R.src.rpm"
curl -fsS --retry 5 --retry-delay 5 --retry-all-errors -o "$WORK/dovecot-sieve-$V-$R.src.rpm" "$BASE/dovecot-sieve-$V-$R.src.rpm"
chown builder "$WORK"/*.src.rpm

# One spec change. AL2023 only has libunwind 1.4.0: it cannot unwind here, and
# libunwind.so exports a `backtrace` symbol that shadows glibc's working one, so
# linking it breaks both of dovecot's backtrace paths and make check dies in
# test-backtrace. libunwind is used by src/lib/backtrace-string.c and nothing
# else, for crash backtraces only. Without it, make check passes.
build rpm -i --define "_topdir $TOP" "$WORK/dovecot-$V-$R.src.rpm"
sed -i -e 's/--with-libunwind /--without-libunwind /' \
       -e '/^BuildRequires: libunwind-devel$/d' \
       -e '/^Requires: libunwind$/d' "$TOP/SPECS/dovecot.spec"
grep -q -- '--without-libunwind' "$TOP/SPECS/dovecot.spec"

dnf -y builddep "$TOP/SPECS/dovecot.spec"
build rpmbuild -ba --define "_topdir $TOP" "$TOP/SPECS/dovecot.spec"

# Sieve build-requires the dovecot-devel just built. Its spec is unmodified.
# Install the whole core set, not just dovecot and dovecot-devel: those two need
# libraries that live in the lua and gssapi subpackages.
mapfile -t core < <(find "$TOP/RPMS" -name '*.rpm' \
    ! -name '*-debuginfo-*' ! -name '*-debugsource-*' ! -name 'al2023-mariadb-devel-compat-*')
dnf -y install "${core[@]}"
dnf -y builddep "$WORK/dovecot-sieve-$V-$R.src.rpm"
build rpmbuild --rebuild --define "_topdir $TOP" "$WORK/dovecot-sieve-$V-$R.src.rpm"

mkdir -p "$DEST"
find "$TOP/RPMS" -name '*.rpm' ! -name 'al2023-mariadb-devel-compat-*' \
    -exec mv -t "$DEST" {} +
ls -1 "$DEST"
