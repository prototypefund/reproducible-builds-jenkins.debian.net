#!/bin/sh

set -e

# generally interesting: BUILD_* JENKINS_* JOB_* but most is in BUILD_URL, so:
export | grep -E "(BUILD_URL=)" || :
TMPFILE=$(mktemp)
trap 'rm "$TMPFILE"' EXIT

curl https://jenkins.debian.net/jnlpJars/jenkins-cli.jar -o "$TMPFILE"
java -jar "$TMPFILE" -s http://localhost:8080/ set-build-result aborted
