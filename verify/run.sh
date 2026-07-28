#!/bin/bash
# Install the built RPMs on AL2023 and start Dovecot in the foreground.
#
#   verify/run.sh /path/to/rpms
#
# Run on AL2023 as root (a container is fine). Listens on 127.0.0.1:143, :993
# and :24 (LMTP) as test@example.com / testpass. Runs until killed.
#
# This exists to put the built packages in front of a real IMAP client. make
# check tests Dovecot's own code; it never opens a TLS session, indexes
# anything in Xapian, delivers over LMTP or runs a Sieve script. The first two
# run against AL2023's OpenSSL and Xapian, which no other Dovecot build uses;
# the other two are whole daemons the packages ship. Those are what this
# project has to check.

set -eux -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
RPMS=${1:?usage: run.sh <directory of RPMs>}

# dovecot-flatcurve needs Xapian, which AL2023 carries in SPAL.
dnf -y install spal-release
dnf -y install openssl shadow-utils
# Everything, debuginfo included: it costs little and helps if dovecot crashes.
dnf -y install "$RPMS"/*.rpm

getent passwd vmail >/dev/null || useradd -u 5000 -d /var/vmail -s /sbin/nologin -M vmail
install -d -o vmail -g vmail -m 0700 /var/vmail

# Two self-signed certs: the default one, and one served only to clients that
# send SNI=imap-sni.example.com. EC rather than RSA so the ECDHE-ECDSA suites
# in dovecot.conf's cipher list are usable at TLS 1.2, not just TLS 1.3.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -nodes -days 1 -subj /CN=localhost \
    -keyout /etc/dovecot/test.key -out /etc/dovecot/test.crt
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -nodes -days 1 -subj /CN=imap-sni.example.com \
    -keyout /etc/dovecot/test-sni.key -out /etc/dovecot/test-sni.crt

printf 'test@example.com:%s::::::\n' "$(doveadm pw -s SHA512-CRYPT -p testpass)" \
    > /etc/dovecot/test-users
chmod 0640 /etc/dovecot/test-users
chgrp dovecot /etc/dovecot/test-users

# The global before-script the LMTP service runs. Compiled here because the
# LMTP process drops privileges and cannot write bytecode into /etc/dovecot.
install -d -m 0755 /etc/dovecot/sieve
install -m 0644 "$HERE/lmtp-before.sieve" /etc/dovecot/sieve/lmtp-before.sieve

# The packaged conf.d enables protocols this config sets up itself.
mv /etc/dovecot/conf.d /etc/dovecot/conf.d.packaged
sed "s/@VERSION@/$(rpm -q --qf '%{version}' dovecot)/" \
    "$HERE/dovecot.conf" > /etc/dovecot/dovecot.conf

# After the config is in place: sievec reads it.
sievec /etc/dovecot/sieve/lmtp-before.sieve

doveconf -n
exec dovecot -F
