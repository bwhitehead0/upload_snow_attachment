#!/bin/bash

# Function to print error messages with a timestamp
err() {
  printf '%s\n' "$(date +'%Y-%m-%dT%H:%M:%S.%3N%z') - Error - $1" >&2
}

# Function to print debug messages with a timestamp if debugging is enabled
dbg() {
  if [[ "$DEBUG" == "true" ]]; then
    printf '%s\n' "$(date +'%Y-%m-%dT%H:%M:%S.%3N%z') - Debug - $1" >&2
  fi
}

# Function to check if a required application is installed
check_application_installed() {
  dbg "check_application_installed(): Checking if $1 is installed."
  if [ -x "$(command -v "${1}")" ]; then
    true
  else
    false
  fi
}

# Function to authenticate with the OAuth endpoint and retrieve a bearer token
token_auth() {
  local OPTIND=1
  local username=""
  local password=""
  local client_id=""
  local client_secret=""
  local oauth_URL=""
  local timeout="60"
  local response=""
  local bearer_token=""
  local grant_type="password"
  
  while getopts ":u:p:C:S:O:o:g:" arg; do
    case "${arg}" in
      u) username="${OPTARG}" ;;
      p) password="${OPTARG}" ;;
      C) client_id="${OPTARG}" ;;
      S) client_secret="${OPTARG}" ;;
      O) oauth_URL="${OPTARG}" ;;
      o) timeout="${OPTARG}" ;;
      g) grant_type="${OPTARG}" ;;
      *) err "Invalid option: -$OPTARG"; exit 1 ;;
    esac
  done
  
  dbg "token_auth(): Attempting to authenticate with OAuth."
  response=$(curl -s -k --location -w "\n%{http_code}" -X POST -d "grant_type=$grant_type" -d "username=$username" -d "password=$password" -d "client_id=$client_id" -d "client_secret=$client_secret" "$oauth_URL")
  body=$(echo "$response" | sed '$d')
  code=$(echo "$response" | tail -n1)
  
  if [[ "$code" =~ ^2 ]]; then
    bearer_token=$(echo "$body" | jq -r '.access_token')
    echo "$bearer_token"
  else
    err "Token authentication failed. HTTP response code: $code"
    exit 1
  fi
}

# Function to upload an attachment to a ServiceNow record
upload_attachment() {
  # https://www.servicenow.com/docs/bundle/xanadu-api-reference/page/integrate/inbound-rest/concept/c_AttachmentAPI.html#title_attachment-POST-file
  local OPTIND=1
  # TODO: replace record_sys_id with change number, or, accept either into the primary function and fetch the sys_id like we do in other scripts
  # ? will we always already have the sys_id? possibly not?
  # ! basename or realpath for file_path in upload command?
  # will likely need to support encryption_context in future state
  local OPTIND=1
  local record_sys_id=""
  local file_path=""
  local sn_url=""
  local bearer_token=""
  local timeout="60"
  local api_endpoint="api/now/attachment/file"
  
  while getopts ":r:f:l:B:t:" arg; do
    case "${arg}" in
      r) record_sys_id="${OPTARG}" ;;
      f) file_path="${OPTARG}" ;;
      l) sn_url="${OPTARG}" ;;
      B) bearer_token="${OPTARG}" ;;
      t) timeout="${OPTARG}" ;;
      :) err "Option -$OPTARG requires an argument."; exit 1 ;;
      ?) err "Invalid option: -$OPTARG"; exit 1 ;;
    esac
  done
  
  api_URL="${sn_url}/${api_endpoint}?table_name=change_request&table_sys_id=${record_sys_id}&file_name=$(basename "$file_path")"
  
  response=$(curl -s -k --location -w "\n%{http_code}" -X POST -H "Authorization: Bearer ${bearer_token}" -H "Content-Type: multipart/form-data" -F "file=@${file_path}" "${api_URL}")
  body=$(printf '%s' "$response" | sed '$d')
  code=$(echo "$response" | tail -n1)
  
  if [[ "$code" =~ ^2 ]]; then
    printf '%s\n' "$body"
  else
    err "Failed to upload attachment. HTTP response code: $code"
    exit 1
  fi
}

# Main function to orchestrate the script's execution
main() {
  local sn_url=""
  local username=""
  local password=""
  local timeout="60"
  local oauth_endpoint="oauth_token.do"
  local client_id=""
  local client_secret=""
  local bearer_token=""
  local file_path=""
  local record_sys_id=""
  DEBUG_PASS=false
  
  while getopts ":u:p:C:S:l:t:f:r:D:P" arg; do
    case "${arg}" in
      D) DEBUG="${OPTARG}" ;;
      P) DEBUG_PASS=true ;;
      u) username="${OPTARG}" ;;
      p) password="${OPTARG}" ;;
      C) client_id="${OPTARG}" ;;
      S) client_secret="${OPTARG}" ;;
      l) sn_url="${OPTARG}" ;;
      t) timeout="${OPTARG}" ;;
      f) file_path="${OPTARG}" ;;
      r) record_sys_id="${OPTARG}" ;;
      :) err "Option -$OPTARG requires an argument."; exit 1 ;;
      ?) err "Invalid option: -$OPTARG"; exit 1 ;;
    esac
  done
  
  export DEBUG
  export DEBUG_PASS
  
  if [[ -z "$record_sys_id" || -z "$sn_url" || -z "$file_path" || ( -z "$username" && -z "$password" ) || ( -z "$username" && -z "$password" && -z "$client_id" && -z "$client_secret" ) ]]; then
    err "main(): Missing required parameters: record_sys_id, sn_url, file_path, and either Username and Password, or Username + Password + Client ID + Client Secret."
    exit 1
  fi
  
  if ! check_application_installed jq; then
    err "jq not available, aborting."
    exit 1
  fi
  if ! check_application_installed curl; then
    err "curl not available, aborting."
    exit 1
  fi
  
  bearer_token=$(token_auth -u "$username" -p "$password" -C "$client_id" -S "$client_secret" -O "${sn_url}/${oauth_endpoint}" -o "$timeout")
  
  upload_attachment -r "$record_sys_id" -f "$file_path" -l "$sn_url" -B "$bearer_token" -t "$timeout"
}

main "$@"