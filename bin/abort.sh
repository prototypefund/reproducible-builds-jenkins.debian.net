#!/bin/sh

set -e

# if we are in a remote node, return a special code so that jenkins_master_wrapper
# can abort the job for us (this assumes everything has been `exec`ed all the
# way to us, and that our pared is sshd itself).
if [ -n "$SSH_ORIGINAL_COMMAND" ] && [ -z "${JENKINS_URL-}" ]; then
    exit 123
fi

# generally interesting: BUILD_* JENKINS_* JOB_* but most is in BUILD_URL, so:
export | grep -E "(BUILD_URL=)" || :
TMPFILE=$(mktemp)
trap 'rm "$TMPFILE"' EXIT

curl https://jenkins.debian.net/jnlpJars/jenkins-cli.jar -o "$TMPFILE"
java -jar "$TMPFILE" -s http://localhost:8080/ set-build-result aborted
