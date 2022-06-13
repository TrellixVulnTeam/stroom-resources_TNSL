#!/usr/bin/env bash

############################################################################
# 
#  Copyright 2019 Crown Copyright
# 
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# 
############################################################################

# Copies the necessary assets into the stack

set -e

# shellcheck disable=SC1091
source lib/shell_utils.sh

DOWNLOAD_DIR="/tmp/stroom_stack_build_downloads"

debug_value() {
  local name="$1"; shift
  local value="$1"; shift
  
  if [ "${IS_DEBUG}" = true ]; then
    echo -e "${DGREY}DEBUG ${name}: ${value}${NC}"
  fi
}

debug() {
  local str="$1"; shift
  
  if [ "${IS_DEBUG}" = true ]; then
    echo -e "${DGREY}DEBUG ${str}${NC}"
  fi
}

# Downloads the file to a temporary directory then copies it from their
# to speed up repeated runs
# NOTE: This assumes the file being downloaded is immutable
download_file() {
  local -r dest_dir=$1
  local -r url_base=$2
  local -r filename=$3
  local -r new_filename="${4:-$filename}"
  local url="${url_base}/${filename}"

  # replace '/' in url with '_' so we can save it as a file
  local url_as_filename="${url//\//_}"

  local download_file_path="${DOWNLOAD_DIR}/${url_as_filename}"

  mkdir -p "${DOWNLOAD_DIR}"
  mkdir -p "${dest_dir}"

  if [ ! -f "${download_file_path}" ]; then

    # File doesn't exist in downloads dir so download it first
    echo -e "    Downloading ${BLUE}${url}${NC}" \
      "${YELLOW}=>${NC} ${BLUE}${download_file_path}${NC}"

    wget \
      --quiet \
      --output-document="${download_file_path}" \
      "${url}"
  fi

  # Now copy file from the downloads dir
  copy_file_to_dir "${download_file_path}" "${dest_dir}" "${new_filename}"

  if [[ "${new_filename}" =~ .*\.sh$ ]]; then
    chmod u+x "${dest_dir}/${new_filename}"
  fi
}

download_stroom_docs() {
  local extra_curl_args=()

  # DO NOT echo this variable
  if [[ -n "${GH_PERSONAL_ACCESS_TOKEN}" ]]; then
    echo -e "    Making authenticated Github API request"
    extra_curl_args=( \
      "-u" \
      "username:${GH_PERSONAL_ACCESS_TOKEN}" )
  else
    echo -e "    GH_PERSONAL_ACCESS_TOKEN not set, making un-authenticated" \
      "Github API request (will be subject to rate limiting)"
  fi

  local zip_url
  # get the highest version number of the stroom-docs releases
  zip_url="$( \
    curl \
      "${extra_curl_args[@]}" \
      --silent \
      --location \
      https://api.github.com/repos/gchq/stroom-docs/releases/latest \
    | jq -r ".assets[] | select(.name | test(\"^stroom-docs-.*_stroom-.*${STROOM_DOCS_STROOM_VERSION}\\\\.zip$\")) .browser_download_url" \
    | tail -1)"

  debug_value "zip_url" "${zip_url}"

  local zip_url_base="${zip_url%/*}" # remove last / and onwards
  local zip_filename="${zip_url##*/}" # remove up to and including last /
  local dest_dir="${VOLUMES_DIRECTORY}/nginx/html/stroom-docs"
  local zip_file="${dest_dir}/${zip_filename}"

  mkdir -p "${dest_dir}"

  download_file \
    "${dest_dir}" \
    "${zip_url_base}" \
    "${zip_filename}"

  unzip \
    -qq \
    -d "${dest_dir}" \
    "${zip_file}"

  # As the schema docs are now local to us we need to change any links to
  # the schema docs on github to our local path
  echo -e "    Replacing ${BLUE}${SCHEMA_DOCS_URL_BASE}${NC} with" \
    "${BLUE}${LOCAL_SCHEMA_DOCS_URL_BASE}${NC} in all HTML files in" \
    "${BLUE}${dest_dir}${NC}"

  find \
      "${dest_dir}" \
      -type f \
      -name "*.html" \
      -print0 \
    | xargs \
      -0 \
      sed \
        -i'' \
        "s#<a href=\"${SCHEMA_DOCS_URL_BASE}#<a href=\"${LOCAL_SCHEMA_DOCS_URL_BASE}#g"

  rm "${zip_file}"
}

download_schema_docs() {
  local extra_curl_args=()

  # DO NOT echo this variable
  if [[ -n "${GH_PERSONAL_ACCESS_TOKEN}" ]]; then
    echo -e "    Making authenticated Github API request"
    extra_curl_args=( \
      "-u" \
      "username:${GH_PERSONAL_ACCESS_TOKEN}" )
  else
    echo -e "    GH_PERSONAL_ACCESS_TOKEN not set, making un-authenticated" \
      "Github API request (will be subject to rate limiting)"
  fi

  local latest_docs_build_number
  # get the highest version number of the stroom-docs releases
  latest_docs_build_number="$( \
    curl \
      "${extra_curl_args[@]}" \
      --silent \
      --location \
      http https://api.github.com/repos/gchq/event-logging-schema/releases \
      | jq -r '.[].tag_name | select(. | test("^docs-v"))' \
      | sed 's/^docs-v//' \
      | sort -n \
      | tail -n1)"

  if [[ -z "${latest_docs_build_number}" ]]; then
    echo -e "    ${RED}ERROR${NC}: Can't establish latest_docs_build_number${NC}"
    exit 1
  fi

  debug_value "latest_docs_build_number" "${latest_docs_build_number}"

  local releases_by_tag_url="https://api.github.com/repos/gchq/event-logging-schema/releases/tags/docs-v${latest_docs_build_number}"
  debug_value "releases_by_tag_url" "${releases_by_tag_url}"

  local zip_url
  # get the highest version number of the stroom-docs releases
  zip_url="$( \
    curl \
      "${extra_curl_args[@]}" \
      --silent \
      --location \
      "${releases_by_tag_url}" \
    | jq -r ".assets[] | select(.name | test(\"^event-logging-schema-docs-v${latest_docs_build_number}\\\\.zip$\")) .browser_download_url" \
    | tail -1)"

  debug_value "zip_url" "${zip_url}"

  local zip_url_base="${zip_url%/*}" # remove last / and onwards
  local zip_filename="${zip_url##*/}" # remove up to and including last /
  local dest_dir="${VOLUMES_DIRECTORY}/nginx/html/event-logging-schema-docs"
  local zip_file="${dest_dir}/${zip_filename}"

  mkdir -p "${dest_dir}"

  download_file \
    "${dest_dir}" \
    "${zip_url_base}" \
    "${zip_filename}"

  unzip \
    -qq \
    -d "${dest_dir}" \
    "${zip_file}"

  rm "${zip_file}"

  # index.html was there to do a noddy re-direct for github pages
  # but we can use nginx rewrites to point us to /latest/
  rm "${dest_dir}/index.html"
}

copy_file_to_dir() {
  local -r src=$1
  local -r dest_dir=$2
  local -r new_filename=$3
  # src may be a glob so we expand the glob and copy each file it represents
  # so we have visibility of what is being copied
  for src_file in ${src}; do
    echo -e "    Copying ${BLUE}${src_file}${NC} ${YELLOW}=>${NC} ${BLUE}${dest_dir}/${new_filename}${NC}"
    mkdir -p "${dest_dir}"
    if [ ! -e "${src_file}" ]; then
      echo -e "      ${RED}ERROR${NC}: File ${BLUE}${src_file}${NC} doesn't exist${NC}"
      exit 1
    fi
    cp "${src_file}" "${dest_dir}/${new_filename}"
  done
}

delete_file() {
  local file="$1"; shift

  echo -e "    Deleting file ${BLUE}${file}${NC}"
  if [ ! -e "${file}" ]; then
    echo -e "      ${RED}ERROR${NC}: File ${BLUE}${file}${NC} doesn't exist${NC}"
    exit 1
  fi
  rm "${file}"
}

# Removes blocks of conditional content in a file if the content is for a
# service that is not in the stack, e.g. 
# 
#   X=Y
#   # ------------IF_stroom_IN_STACK------------
#   STROOM_BASE_LOGS_DIR="${ROOT_LOGS_DIR}/stroom"
#   # ------------FI_stroom_IN_STACK------------
#   Y=Z
#
# becomes (if stroom is not in the services array)
# 
#   X=Y
#   Y=Z
remove_conditional_content() {
  local file="$1"; shift

  [ -f "${file}" ] \
    || echo -e "      ${RED}ERROR${NC}: File ${BLUE}${file}${NC} doesn't exist${NC}"

  local cond_content_service_regex="(?<=IF_)[^_]+(?=_IN_STACK)"

  while read -r cond_content_service_name; do
    if ! element_in "${cond_content_service_name}" "${services[@]}"; then
      # This content is for a service that is NOT in the stack, so remove it
      echo -e "      Removing conditional content for" \
        "${YELLOW}${cond_content_service_name}${NC} in ${BLUE}${file}${NC}"

      local block_start_regex="IF_${cond_content_service_name}_IN_STACK"
      local block_end_regex="FI_${cond_content_service_name}_IN_STACK"

      # Delete from the start pattern (inc.) to the end pattern (inc.)
      # It will delete multiple blocks for this service
      sed -i "/${block_start_regex}/,/${block_end_regex}/d" "${file}"
    fi
  done < <( \
    grep -oP "${cond_content_service_regex}" "${file}"  \
    | sort  \
    | uniq \
  )

  # All remaining conditional blocks are now valid for our services so
  # remove the IF_ and FI_ tags
  sed -i -r "/(IF|FI)_[^_]+_IN_STACK/d" "${file}"
}

main() {
  setup_echo_colours

  [ "$#" -ge 2 ] || die "${RED}Error${NC}: Invalid arguments, usage:" \
    "${BLUE}build.sh stackName serviceX serviceY etc.${NC}"

  echo -e "${GREEN}Copying assets${NC}"

  # We need access to the release tags for downloading specific versions of files
  # from github
  # shellcheck disable=SC1091
  source container_versions.env

  local -r BUILD_STACK_NAME=$1
  local -r VERSION=$2
  local -r services=( "${@:3}" )
  local -r STROOM_DOCS_STROOM_VERSION="7.0"
  local -r BUILD_DIRECTORY="build/${BUILD_STACK_NAME}"
  local -r WORKING_DIRECTORY="${BUILD_DIRECTORY}/${BUILD_STACK_NAME}-${VERSION}"
  local -r VOLUMES_DIRECTORY="${WORKING_DIRECTORY}/volumes"

  local -r SRC_CERTS_DIRECTORY="../../dev-resources/certs"
  local -r SRC_VOLUMES_DIRECTORY="../../dev-resources/compose/volumes"
  local -r SRC_NGINX_CONF_DIRECTORY="${SRC_VOLUMES_DIRECTORY}/stroom-nginx/conf"
  local -r SRC_NGINX_HTML_DIRECTORY="${SRC_VOLUMES_DIRECTORY}/stroom-nginx/html"
  local -r SRC_ELASTIC_CONF_DIRECTORY="${SRC_VOLUMES_DIRECTORY}/elasticsearch/conf"
  local -r SRC_KIBANA_CONF_DIRECTORY="${SRC_VOLUMES_DIRECTORY}/kibana/conf"
  local -r SRC_STROOM_LOG_SENDER_CONF_DIRECTORY="${SRC_VOLUMES_DIRECTORY}/stroom-log-sender/conf"
  local -r SRC_STROOM_ALL_DBS_CONF_FILE="${SRC_VOLUMES_DIRECTORY}/stroom-all-dbs/conf/stroom-all-dbs.cnf"
  local -r SRC_STROOM_ALL_DBS_INIT_DIRECTORY="${SRC_VOLUMES_DIRECTORY}/stroom-all-dbs/init"
  local -r SEND_TO_STROOM_VERSION="send-to-stroom-v3.1.0"
  local -r SEND_TO_STROOM_URL_BASE="https://github.com/gchq/stroom-clients/releases/download/${SEND_TO_STROOM_VERSION}"

  local -r STROOM_RELEASES_BASE="https://github.com/gchq/stroom/releases/download/${STROOM_TAG}"
  local -r STROOM_RAW_CONTENT_BASE="https://raw.githubusercontent.com/gchq/stroom/${STROOM_TAG}"
  local -r STROOM_CONFIG_YAML_URL_FILENAME="stroom-app-config-${STROOM_TAG}.yml"
  local -r STROOM_CONFIG_DEFAULTS_YAML_URL_FILENAME="stroom-app-config-defaults-${STROOM_TAG}.yml"
  local -r STROOM_CONFIG_SCHEMA_YAML_URL_FILENAME="stroom-app-config-schema-${STROOM_TAG}.yml"
  local -r STROOM_SNAPSHOT_DOCKER_DIR="${LOCAL_STROOM_REPO_DIR:-UNKNOWN_LOCAL_STROOM_REPO_DIR}/stroom-app/docker/build"
  local -r STROOM_SNAPSHOT_RELEASE_CONFIG_DIR="${LOCAL_STROOM_REPO_DIR:-UNKNOWN_LOCAL_STROOM_REPO_DIR}/stroom-app/build/release/config"

  local -r STROOM_PROXY_RELEASES_BASE="https://github.com/gchq/stroom/releases/download/${STROOM_PROXY_TAG}"
  local -r STROOM_PROXY_CONFIG_YAML_URL_FILENAME="stroom-proxy-app-config-${STROOM_PROXY_TAG}.yml"
  local -r STROOM_PROXY_CONFIG_DEFAULTS_YAML_URL_FILENAME="stroom-proxy-app-config-defaults-${STROOM_PROXY_TAG}.yml"
  local -r STROOM_PROXY_CONFIG_SCHEMA_YAML_URL_FILENAME="stroom-proxy-app-config-schema-${STROOM_PROXY_TAG}.yml"
  local -r STROOM_PROXY_SNAPSHOT_DOCKER_DIR="${LOCAL_STROOM_REPO_DIR:-UNKNOWN_LOCAL_STROOM_REPO_DIR}/stroom-proxy/stroom-proxy-app/docker/build"
  local -r STROOM_PROXY_SNAPSHOT_RELEASE_CONFIG_DIR="${LOCAL_STROOM_REPO_DIR:-UNKNOWN_LOCAL_STROOM_REPO_DIR}/stroom-proxy/stroom-proxy-app/build/release/config"

  local -r CONFIG_YAML_FILENAME="config.yml"
  local -r CONFIG_DEFAULTS_YAML_FILENAME="config-defaults.yml"
  local -r CONFIG_SCHEMA_YAML_FILENAME="config-schema.yml"
  local -r SCHEMA_DOCS_URL_BASE="https://gchq.github.io/event-logging-schema"
  local -r LOCAL_SCHEMA_DOCS_URL_BASE="/event-logging-schema-docs/"

  ############
  #  stroom  #
  ############
  
  if element_in "stroom" "${services[@]}"; then
    echo -e "  Copying ${YELLOW}stroom${NC} config"
    local -r DEST_STROOM_CONFIG_DIRECTORY="${VOLUMES_DIRECTORY}/stroom/config"
    if [[ "${STROOM_TAG}" =~ local-SNAPSHOT ]]; then
      echo -e "    ${RED}WARNING${NC}: Copying a non-versioned local file" \
        "because ${YELLOW}STROOM_TAG${NC}=${BLUE}${STROOM_TAG}${NC}"
      if [ -z "${LOCAL_STROOM_REPO_DIR}" ]; then
        echo -e "    ${RED}${NC}         Set ${YELLOW}LOCAL_STROOM_REPO_DIR${NC} to your local stroom repo"
        echo -e "    ${RED}${NC}         E.g. '${BLUE}export LOCAL_STROOM_REPO_DIR=/home/dev/git_work/stroom${NC}'"
        exit 1
      fi
      if [ ! -d "${STROOM_SNAPSHOT_DOCKER_DIR}" ]; then
        echo -e "    ${RED}${NC}         Can't find ${BLUE}${STROOM_SNAPSHOT_DOCKER_DIR}${NC}, has the stroom build been run?"
        exit 1
      fi
      if [ ! -d "${STROOM_SNAPSHOT_RELEASE_CONFIG_DIR}" ]; then
        echo -e "    ${RED}${NC}         Can't find ${BLUE}${STROOM_SNAPSHOT_RELEASE_CONFIG_DIR}${NC}, has the stroom build been run?"
        exit 1
      fi
      copy_file_to_dir \
        "${STROOM_SNAPSHOT_DOCKER_DIR}/${CONFIG_YAML_FILENAME}" \
        "${DEST_STROOM_CONFIG_DIRECTORY}" \
        "${CONFIG_YAML_FILENAME}"
      copy_file_to_dir \
        "${STROOM_SNAPSHOT_RELEASE_CONFIG_DIR}/${CONFIG_DEFAULTS_YAML_FILENAME}" \
        "${DEST_STROOM_CONFIG_DIRECTORY}" \
        "${CONFIG_DEFAULTS_YAML_FILENAME}"
      copy_file_to_dir \
        "${STROOM_SNAPSHOT_RELEASE_CONFIG_DIR}/${CONFIG_SCHEMA_YAML_FILENAME}" \
        "${DEST_STROOM_CONFIG_DIRECTORY}" \
        "${CONFIG_SCHEMA_YAML_FILENAME}"
    else
      download_file \
        "${DEST_STROOM_CONFIG_DIRECTORY}" \
        "${STROOM_RELEASES_BASE}" \
        "${STROOM_CONFIG_YAML_URL_FILENAME}" \
        "${CONFIG_YAML_FILENAME}"
      download_file \
        "${DEST_STROOM_CONFIG_DIRECTORY}" \
        "${STROOM_RELEASES_BASE}" \
        "${STROOM_CONFIG_DEFAULTS_YAML_URL_FILENAME}" \
        "${CONFIG_DEFAULTS_YAML_FILENAME}"
      download_file \
        "${DEST_STROOM_CONFIG_DIRECTORY}" \
        "${STROOM_RELEASES_BASE}" \
        "${STROOM_CONFIG_SCHEMA_YAML_URL_FILENAME}" \
        "${CONFIG_SCHEMA_YAML_FILENAME}"
    fi
  fi

  #########################
  #  stroom-remote-proxy  #
  #########################

  if element_in "stroom-proxy-remote" "${services[@]}"; then
    copy_proxy_config "stroom-proxy-remote"
  fi

  ########################
  #  stroom-proxy-local  #
  ########################

  if element_in "stroom-proxy-local" "${services[@]}"; then
    copy_proxy_config "stroom-proxy-local"
  fi

  ###########
  #  nginx  #
  ###########
  
  if element_in "nginx" "${services[@]}"; then
    echo -e "  Copying ${YELLOW}nginx${NC} certificates"
    local -r DEST_NGINX_CERTS_DIRECTORY="${VOLUMES_DIRECTORY}/nginx/certs"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/certificate-authority/ca.pem.crt" \
      "${DEST_NGINX_CERTS_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/server/server.pem.crt" \
      "${DEST_NGINX_CERTS_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/server/server.unencrypted.key" \
      "${DEST_NGINX_CERTS_DIRECTORY}"

    echo -e "  Copying ${YELLOW}nginx${NC} config files"
    local -r DEST_NGINX_CONF_DIRECTORY="${VOLUMES_DIRECTORY}/nginx/conf"
    copy_file_to_dir \
      "${SRC_NGINX_CONF_DIRECTORY}/*.conf.template" \
      "${DEST_NGINX_CONF_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_NGINX_CONF_DIRECTORY}/crontab.txt" \
      "${DEST_NGINX_CONF_DIRECTORY}"

    # We need a custom nginx.conf for the stroom_proxy stack as that is just
    # proxy and nginx.
    if [ "${BUILD_STACK_NAME}" = "stroom_proxy" ]; then
      echo -e "  Overriding ${YELLOW}stroom-nginx${NC} configuration for stroom_proxy stack"
      copy_file_to_dir \
        "${SRC_NGINX_CONF_DIRECTORY}/custom/proxy_nginx.conf.template" \
        "${DEST_NGINX_CONF_DIRECTORY}" \
        "nginx.conf.template"

      # Remove files not applicable to the remote proxy stack
      delete_file \
        "${DEST_NGINX_CONF_DIRECTORY}/locations.stroom.conf.template" 
      delete_file \
        "${DEST_NGINX_CONF_DIRECTORY}/upstreams.stroom.processing.conf.template" 
      delete_file \
        "${DEST_NGINX_CONF_DIRECTORY}/upstreams.stroom.ui.conf.template" 
    fi

    # Delete the dev conf file as this is not applicable to a released
    # stack
    delete_file \
      "${DEST_NGINX_CONF_DIRECTORY}/locations.dev.conf.template" 

    # Remove the reference to the dev locations file
    remove_conditional_content \
      "${DEST_NGINX_CONF_DIRECTORY}/nginx.conf.template" 

    echo -e "  Copying ${YELLOW}nginx${NC} html files"
    local -r DEST_NGINX_HTML_DIRECTORY="${VOLUMES_DIRECTORY}/nginx/html"
    copy_file_to_dir \
      "${SRC_NGINX_HTML_DIRECTORY}/50x.html" \
      "${DEST_NGINX_HTML_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_NGINX_HTML_DIRECTORY}/index.html" \
      "${DEST_NGINX_HTML_DIRECTORY}"

    # Donload the latest stroom-docs zip and unpack it in volumes/nginx/html
    download_stroom_docs
    download_schema_docs
  fi

  #############################
  #  stroom / stroom-proxy-*  #
  #############################
  
  if element_in "stroom" "${services[@]}" \
    || element_in "stroom-proxy-local" "${services[@]}" \
    || element_in "stroom-proxy-remote" "${services[@]}"; then

    # Set up the client certs needed for the send_data script
    echo -e "  Copying ${YELLOW}client${NC} certificates"
    local -r DEST_CLIENT_CERTS_DIRECTORY="${WORKING_DIRECTORY}/certs"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/certificate-authority/ca.pem.crt" \
      "${DEST_CLIENT_CERTS_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/client/client.pem.crt" \
      "${DEST_CLIENT_CERTS_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/client/client.unencrypted.key" \
      "${DEST_CLIENT_CERTS_DIRECTORY}"

    # Get the send_to_stroom* scripts we need for the send_data script
    echo -e "  Copying ${YELLOW}send_to_stroom${NC} script"
    local -r DEST_LIB_DIR="${WORKING_DIRECTORY}/lib"
    download_file \
      "${DEST_LIB_DIR}" \
      "${SEND_TO_STROOM_URL_BASE}" \
      "send_to_stroom.sh"
    download_file \
      "${DEST_LIB_DIR}" \
      "${SEND_TO_STROOM_URL_BASE}" \
      "send_to_stroom_args.sh"
  fi

  ####################
  #  elastic-search  #
  ####################
  
  # If elasticsearch is in the list of services add its volume
  if element_in "elasticsearch" "${services[@]}"; then
    echo -e "  Copying ${YELLOW}elasticsearch${NC} config files"
    local -r DEST_ELASTIC_CONF_DIRECTORY="${VOLUMES_DIRECTORY}/elasticsearch/conf"
    mkdir -p "${DEST_ELASTIC_CONF_DIRECTORY}"
    cp ${SRC_ELASTIC_CONF_DIRECTORY}/* "${DEST_ELASTIC_CONF_DIRECTORY}"
  fi

  #######################
  #  stroom-log-sender  #
  #######################
  
  # If stroom-log-sender is in the list of services add its volume
  if element_in "stroom-log-sender" "${services[@]}"; then

    echo -e "  Copying ${YELLOW}stroom-log-sender${NC} certificates"
    local -r DEST_STROOM_LOG_SENDER_CERTS_DIRECTORY="${VOLUMES_DIRECTORY}/stroom-log-sender/certs"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/certificate-authority/ca.pem.crt" \
      "${DEST_STROOM_LOG_SENDER_CERTS_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/client/client.pem.crt" \
      "${DEST_STROOM_LOG_SENDER_CERTS_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_CERTS_DIRECTORY}/client/client.unencrypted.key" \
      "${DEST_STROOM_LOG_SENDER_CERTS_DIRECTORY}"

    echo -e "  Copying ${YELLOW}stroom-log-sender${NC} config files"
    local -r DEST_STROOM_LOG_SENDER_CONF_DIRECTORY="${VOLUMES_DIRECTORY}/stroom-log-sender/conf"
    copy_file_to_dir \
      "${SRC_STROOM_LOG_SENDER_CONF_DIRECTORY}/config.yml" \
      "${DEST_STROOM_LOG_SENDER_CONF_DIRECTORY}"
    remove_conditional_content "${DEST_STROOM_LOG_SENDER_CONF_DIRECTORY}/config.yml"
  fi

  ####################
  #  stroom-all-dbs  #
  ####################
  
  if element_in "stroom-all-dbs" "${services[@]}"; then
    echo -e "  Copying ${YELLOW}stroom-all-dbs${NC} config file"
    local -r DEST_STROOM_ALL_DBS_CONF_DIRECTORY="${VOLUMES_DIRECTORY}/stroom-all-dbs/conf"
    local -r DEST_SCRIPTS_DIRECTORY="${WORKING_DIRECTORY}/scripts"
    copy_file_to_dir "${SRC_STROOM_ALL_DBS_CONF_FILE}" "${DEST_STROOM_ALL_DBS_CONF_DIRECTORY}"

    echo -e "  Copying ${YELLOW}stroom-all-dbs${NC} init files"
    local -r DEST_STROOM_ALL_DBS_INIT_DIRECTORY="${VOLUMES_DIRECTORY}/stroom-all-dbs/init"
    copy_file_to_dir \
      "${SRC_STROOM_ALL_DBS_INIT_DIRECTORY}/000_stroom_init.sh" \
      "${DEST_STROOM_ALL_DBS_INIT_DIRECTORY}"
    copy_file_to_dir \
      "${SRC_STROOM_ALL_DBS_INIT_DIRECTORY}/stroom/001_create_databases.sql.template" \
      "${DEST_STROOM_ALL_DBS_INIT_DIRECTORY}/stroom"


    if [[ ! "${STROOM_TAG}" =~ local-SNAPSHOT ]]; then
      local -r SCRIPTS_BASE_URL="${STROOM_RAW_CONTENT_BASE}/scripts"
      download_file \
        "${DEST_SCRIPTS_DIRECTORY}" \
        "${SCRIPTS_BASE_URL}" \
        "v7_auth_db_table_rename.sql"
      download_file \
        "${DEST_SCRIPTS_DIRECTORY}" \
        "${SCRIPTS_BASE_URL}" \
        "v7_db_pre_migration_checks.sql"
      download_file \
        "${DEST_SCRIPTS_DIRECTORY}" \
        "${SCRIPTS_BASE_URL}" \
        "v7_drop_unused_databases.sql"
    else
      echo -e "  ${RED}WARNING${NC}: Skipping download of DB migration scripts as this is a SNAPSHOT version"
    fi
  fi

  ############
  #  kibana  #
  ############

  # If kibana is in the list of services add its volume
  if element_in "kibana" "${services[@]}"; then
    echo -e "  Copying ${YELLOW}kibana${NC} config files"
    local -r DEST_KIBANA_CONF_DIRECTORY="${VOLUMES_DIRECTORY}/kibana/conf"
    mkdir -p "${DEST_KIBANA_CONF_DIRECTORY}"
    cp ${SRC_KIBANA_CONF_DIRECTORY}/* "${DEST_KIBANA_CONF_DIRECTORY}"
  fi

}

copy_proxy_config() {
  local service_name="$1"; shift
  
  echo -e "  Copying ${YELLOW}${service_name}${NC} config"
  local -r dest_config_dir="${VOLUMES_DIRECTORY}/${service_name}/config"
  if [[ "${STROOM_PROXY_TAG}" =~ local-SNAPSHOT ]]; then
    echo -e "    ${RED}WARNING${NC}: Copying a non-versioned local file" \
      "because ${YELLOW}STROOM_PROXY_TAG${NC}=${BLUE}${STROOM_PROXY_TAG}${NC}"
    if [ -z "${LOCAL_STROOM_REPO_DIR}" ]; then
      echo -e "    ${RED}${NC}         Set ${YELLOW}LOCAL_STROOM_REPO_DIR${NC}" \
        "to your local stroom repo"
      echo -e "    ${RED}${NC}         E.g. '${BLUE}export" \
        "LOCAL_STROOM_REPO_DIR=/home/dev/git_work/stroom${NC}'"
      exit 1
    fi
    if [ ! -d "${STROOM_PROXY_SNAPSHOT_DOCKER_DIR}" ]; then
      echo -e "    ${RED}${NC}         Can't find" \
        "${BLUE}${STROOM_PROXY_SNAPSHOT_DOCKER_DIR}${NC}, has the stroom" \
        "build been run?"
      exit 1
    fi
    if [ ! -d "${STROOM_PROXY_SNAPSHOT_RELEASE_CONFIG_DIR}" ]; then
      echo -e "    ${RED}${NC}         Can't find" \
        "${BLUE}${STROOM_PROXY_SNAPSHOT_RELEASE_CONFIG_DIR}${NC}, has" \
        "the stroom build been run?"
      exit 1
    fi
    copy_file_to_dir \
      "${STROOM_PROXY_SNAPSHOT_DOCKER_DIR}/${CONFIG_YAML_FILENAME}" \
      "${dest_config_dir}" \
      "${CONFIG_YAML_FILENAME}"
    copy_file_to_dir \
      "${STROOM_PROXY_SNAPSHOT_RELEASE_CONFIG_DIR}/${CONFIG_DEFAULTS_YAML_FILENAME}" \
      "${dest_config_dir}" \
      "${CONFIG_DEFAULTS_YAML_FILENAME}"
    copy_file_to_dir \
      "${STROOM_PROXY_SNAPSHOT_RELEASE_CONFIG_DIR}/${CONFIG_SCHEMA_YAML_FILENAME}" \
      "${dest_config_dir}" \
      "${CONFIG_SCHEMA_YAML_FILENAME}"
  else
    download_file \
      "${dest_config_dir}" \
      "${STROOM_PROXY_RELEASES_BASE}" \
      "${STROOM_PROXY_CONFIG_YAML_URL_FILENAME}" \
      "${CONFIG_YAML_FILENAME}"
    download_file \
      "${dest_config_dir}" \
      "${STROOM_PROXY_RELEASES_BASE}" \
      "${STROOM_PROXY_CONFIG_DEFAULTS_YAML_URL_FILENAME}" \
      "${CONFIG_DEFAULTS_YAML_FILENAME}"
    download_file \
      "${dest_config_dir}" \
      "${STROOM_PROXY_RELEASES_BASE}" \
      "${STROOM_PROXY_CONFIG_SCHEMA_YAML_URL_FILENAME}" \
      "${CONFIG_SCHEMA_YAML_FILENAME}"
  fi

  echo -e "  Copying ${YELLOW}${service_name}${NC} certificates"
  local -r dest_certs_dir="${VOLUMES_DIRECTORY}/${service_name}/certs"
  copy_file_to_dir \
    "${SRC_CERTS_DIRECTORY}/certificate-authority/ca.jks" \
    "${dest_certs_dir}"
  # client keystore so it can forward to stroom(?:-proxy)? and make
  # rest calls
  copy_file_to_dir \
    "${SRC_CERTS_DIRECTORY}/client/client.jks" \
    "${dest_certs_dir}"
}

main "$@"
