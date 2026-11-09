#!/usr/bin/env bash
#
# Maven deploy for a branch or a release tag. Run it from the root of the project.
# It only runs "mvn deploy": no version change, no commit, no tag, no push.
#
# Usage:
#   maven-central-release.sh [--dry-run]
#
# Environment (optional):
#   TAG_PREFIXES     release tag prefixes, default "legacy-v v"
#   DEPLOY_PROFILE   Maven profile used for a tag build
#   NEXUS_SERVER_ID  Maven server id used for a branch build
#   MAVEN_SNAPSHOT_URL  snapshot repository URL used for a branch build
#
# The script never reads, writes or prints credentials.

set -euo pipefail

TAG_PREFIXES="${TAG_PREFIXES:-legacy-v v}"
VERSION_PATTERN='[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?'
DEPLOY_PROFILE="${DEPLOY_PROFILE:-central-publishing}"
NEXUS_SERVER_ID="${NEXUS_SERVER_ID:-maven-private}"

DRY_RUN=false

usage() {
  awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "$0"
  exit "${1:-1}"
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage 1 ;;
  esac
done

run() {
  echo "+ $*"
  if [ "$DRY_RUN" = false ]; then
    "$@"
  fi
}

# Prints the version of a release tag (<prefix><version>), or nothing if the tag does not follow the pattern.
version_from_tag() {
  local tag="$1" prefix
  for prefix in $TAG_PREFIXES; do
    if [[ "$tag" =~ ^${prefix}(${VERSION_PATTERN})$ ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  done
  return 1
}

project_version() {
  mvn -B -q -DforceStdout help:evaluate -Dexpression=project.version
}

# Tag build.
deploy_to_central() {
  local tag="$1" tag_version pom_version

  if ! tag_version="$(version_from_tag "$tag")"; then
    echo "ERROR: tag '$tag' is not a release tag; expected one of: $(for p in $TAG_PREFIXES; do printf '%s<major>.<minor>.<patch> ' "$p"; done)" >&2
    exit 1
  fi

  pom_version="$(project_version)"
  if [ "$pom_version" != "$tag_version" ]; then
    echo "ERROR: tag '$tag' does not match pom.xml version '$pom_version'" >&2
    exit 1
  fi

  echo "Deploying version $tag_version from tag $tag"
  run mvn -B -P"$DEPLOY_PROFILE" clean deploy
}

# Branch build.
deploy_to_nexus() {
  local branch="$1" pom_version

  if [ -z "${MAVEN_SNAPSHOT_URL:-}" ] && [ "$DRY_RUN" = false ]; then
    echo "ERROR: MAVEN_SNAPSHOT_URL is not set (needed to deploy branch '$branch')" >&2
    exit 1
  fi

  pom_version="$(project_version)"
  case "$pom_version" in
    *-SNAPSHOT) ;;
    *)
      echo "Skipping deploy of branch '$branch': pom.xml version '$pom_version' is not a -SNAPSHOT version"
      return 0
      ;;
  esac

  echo "Deploying version $pom_version from branch $branch to the snapshot repository"
  run mvn -B clean deploy -DskipTests \
    "-DaltDeploymentRepository=${NEXUS_SERVER_ID}::default::${MAVEN_SNAPSHOT_URL:-<MAVEN_SNAPSHOT_URL>}"
}

cd "$(git rev-parse --show-toplevel)"

REF_TYPE="${GITHUB_REF_TYPE:-}"
REF_NAME="${GITHUB_REF_NAME:-}"
if [ -z "$REF_TYPE" ]; then
  REF_NAME="$(git describe --tags --exact-match 2>/dev/null || true)"
  if [ -n "$REF_NAME" ]; then
    REF_TYPE=tag
  else
    REF_TYPE=branch
    REF_NAME="$(git rev-parse --abbrev-ref HEAD)"
  fi
fi

if [ "$REF_TYPE" = tag ]; then
  deploy_to_central "$REF_NAME"
else
  deploy_to_nexus "$REF_NAME"
fi

echo "Done."
