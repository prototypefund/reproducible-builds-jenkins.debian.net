#!/bin/sh

# agent.jar has to be downloaded from http://localhost/jnlpJars/agent.jar

# There doesn't seem to be any better way to figure out the agent name
# from here, let's just hope all WORKSPACE have been set correctly
NODE_NAME="$(basename "${WORKSPACE}")"

echo "Starting agent.jar for ${NODE_NAME}..."

f="/var/lib/jenkins/offline_nodes"
if [ -f "$f" ]; then
    if grep -q "$NODE_NAME" "$f"; then
        echo "This node is currently marked as offline, not starting agent.jar"
        exit 1
    fi
fi

echo "This jenkins agent.jar will run as PID $$."
JAVA_ARGS="-Xms1G -Xmx2G"
# shellcheck disable=SC2086
exec java $JAVA_ARGS -jar /var/lib/jenkins/agent.jar
