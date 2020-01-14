#!/usr/bin/env bash
#
# Builds a stack of stroom services using the default configuration from the yaml.
# This stack assumes you have existing instances of stroom and a database.

set -e

main() {
  local -r VERSION=$1
  local -r BUILD_STACK_NAME="stroom_services"

  local SERVICES=()

  # Define all the services that make up the stack
  # Array created like this to allow lines to commneted out
  SERVICES+=("nginx")
  SERVICES+=("stroom-auth-service")
  SERVICES+=("stroom-auth-ui")
  SERVICES+=("stroom-log-sender")

  ./build.sh "${BUILD_STACK_NAME}" "${VERSION:-SNAPSHOT}" "${SERVICES[@]}"
}

main "$@"
