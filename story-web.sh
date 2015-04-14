#!/usr/bin/env bash

set -o pipefail -u

WAIT_NUM_ATTEMPTS=20
WAIT_DELAY_SEC=0.5
SERVICE_NAME=story-webapp
BASE_DIR=/Users/Ian1/workspace/story-webapp
ENV_NAME=development_aws_catalog
DEFAULT_PID_FILE_REL_PATH=log/story-web.pid


pid_file="${BASE_DIR}/${DEFAULT_PID_FILE_REL_PATH}"
log_dir="${BASE_DIR}/log"





is_pid_running() {
  kill -0 "$1" 2>/dev/null
}

write_pid_to_file() {
  mkdir -p $(dirname "${pid_file}")
  echo "$1" > "${pid_file}"
}

read_pid_file() {
  service_pid=""
  if [ -f "${pid_file}" ]; then
    service_pid=$( <"${pid_file}" )
    if ! is_pid_running "${service_pid}"; then
      echo "Process ${service_pid} is not running, removing ${pid_file}" >&2
      rm -f "${pid_file}"
      service_pid=""
    fi
  fi
}

wait_for_condition() {
  local attempts_left=${WAIT_NUM_ATTEMPTS}
  local cmd=( "$@" )
  while [ ${attempts_left} -gt 0 ]; do
    if [ "${cmd[0]}" == "!" ]; then
      if ! "${cmd[@]:1}"; then
        return
      fi
    else
      if "${cmd[@]}"; then
        return
      fi
    fi
    attempts_left=$(( ${attempts_left} - 1 ))
    sleep "${WAIT_DELAY_SEC}"
  done
  return 1
}


start() {
  read_pid_file

  cd "${log_dir}"
  stdout_file="${log_dir}"/story-web.out
  stderr_file="${log_dir}"/story-web.err
  ruby_cmd+=(
    bundle
    exec
    rails
    server -e ${ENV_NAME}
  )

  "${ruby_cmd[@]}" >"${stdout_file}" 2>"${stderr_file}" </dev/null &
  service_pid=$!

  if wait_for_condition is_pid_running "${service_pid}"; then
    echo "${SERVICE_NAME} has started as ${service_pid}."
    write_pid_to_file "${service_pid}"
  else
    echo "${SERVICE_NAME} process ${service_pid} has failed to start." >&2
    echo "Please contact ClearStory Data support at support@clearstorydata.com." >&2
    exit 1
  fi


}

stop() {
  read_pid_file
  if [ -n "${service_pid}" ]; then
    echo "Stopping ${SERVICE_NAME} (pid ${service_pid})"
    kill "${service_pid}"

    if wait_for_condition ! is_pid_running "${service_pid}"; then
      echo "${SERVICE_NAME} has stopped"
      rm -f "${pid_file}"
    else
      echo "Failed to stop ${SERVICE_NAME} with SIGTERM, killing with SIGKILL"
      kill -SIGKILL "${service_pid}"
      rm -f "${pid_file}"
    fi
  else
    echo "${SERVICE_NAME} is not running"
  fi
}

status() {
    read_pid_file
    if [ -n "${service_pid}" ]; then
      echo "${SERVICE_NAME} is running (pid ${service_pid})"
    else
      echo "${SERVICE_NAME} is not running"
    fi
}

show_help() {
  cat <<EOT
Usage: ${0##*/} <command>
Command:
  start  - start the story_web
  stop   - stop the story_web
  status - display the story_web status
  restart - restart the story_web
EOT


}


case $1 in
  start) start ;;
  stop) stop ;;
  restart) stop && start ;;
  status) status ;;
  *)
    echo "Unknown command ${command}" >&2
    show_help >&2
    exit 1
esac
