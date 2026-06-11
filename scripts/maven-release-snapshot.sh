#!/bin/sh
# Script to run Maven deploy with optional module selection or pattern

PROJECT_DIR=$(basename "$GITHUB_REPOSITORY")

if [ -d "$PROJECT_DIR" ]; then
  cd "$PROJECT_DIR"
  echo "Switched to project directory: $(pwd)"
  
  echo "Deploying packages to the snapshot repository..."
  mvn clean deploy -DaltDeploymentRepository=maven-private::default::$MAVEN_SNAPSHOT_URL -DskipTests
else
  echo "Error: Project directory $PROJECT_DIR not found!"
  exit 1
fi