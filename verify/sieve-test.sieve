# Fed to sieve-test, the Pigeonhole project's own script tester, rather than a
# harness written here. Files a matching message into a non-INBOX mailbox, so
# a run that leaves it in INBOX shows fileinto did not execute.
require ["fileinto", "mailbox"];

if header :contains "subject" "SIEVE-VERIFY" {
  fileinto :create "Sieved";
}
