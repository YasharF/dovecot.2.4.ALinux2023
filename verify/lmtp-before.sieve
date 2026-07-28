# Global before-script, run by the LMTP service on every delivery.
#
# :copy files a copy into LmtpSieved without cancelling the implicit keep, so
# the message still lands in INBOX and imaptest's IDLEing client sees the
# delivery it is expecting. A non-empty LmtpSieved afterwards is proof that
# Sieve ran inside the delivery path, not just standalone under sieve-test.
require ["fileinto", "copy", "mailbox"];

fileinto :copy :create "LmtpSieved";
