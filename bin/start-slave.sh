#!/bin/sh

# slave.jar has to be downloaded from http://localhost/jnlpJars/slave.jar

# There doesn't seem to be any better way to figure out the slave name
# from here, let's just hope all WORKSPACE have been set correctly
NODE_NAME="$(basename ${WORKSPACE})"

echo "Starting slave.jar for ${NODE_NAME}..."

f="/var/lib/jenkins/offline_nodes"
if [ -f "$f" ]; then
    if grep -q "$NODE_NAME" "$f"; then
        echo "This node is currently marked as offline, not starting slave.jar"
        exit 1
    fi
fi

echo "This jenkins slave.jar will run as PID $$."
export JAVA_ARGS="-Xms768M -Xmx768M"
export MALLOC_ARENA_MAX=2
#exec java $JAVA_ARGS -jar /var/lib/jenkins/slave.jar
exec java -jar /var/lib/jenkins/slave.jar
