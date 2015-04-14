#!/usr/bin/env bash

set -o pipefail -u
BASE_DIR=/Users/Ian1/workspace/csd-agent/csd-agent/csd-agent-core
SERVICE_NAME=csd-agent-server
DEFAULT_CONF_REL_PATH=../csd-agent-server/local-test-config.yml
DEFAULT_PID_FILE_REL_PATH=run/csd-agent-server.pid

WAIT_NUM_ATTEMPTS=20
WAIT_DELAY_SEC=0.5

show_help() {
  cat <<EOT

Usage: ${0##*/} [options] <command>

Options:

  --conf <conf_path>
    Specifies the agent-server configuration file path.
    ${DEFAULT_CONF_REL_PATH} relative to the agent-server directory is used by default.

  --pid-file
    Specifies an alternative PID file location for the ${SERVICE_NAME} daemon.
    ${DEFAULT_PID_FILE_REL_PATH} relative to the agent-server directory is used by
    default.

Advanced options:

  --debug-log
    Allow debug logging.

  --debug-port <port>
    Allow Java remote debugging on the given port.

  --debug-suspend
    Suspend the agent-server process until the debugger connects.

  --show-command-line[-only]
    Show the agent-server command line that is being run. Optionally, stop after displaying the command
    line.

Command:
  start  - start the agent-server
  stop   - stop the agent-server
  status - display the agent-server status

EOT
}

parse_args() {
  pid_file="${base_dir}/${DEFAULT_PID_FILE_REL_PATH}"

  # Process command-line arguments.
  daemonize=true  # Run in background by default
  command=""
  show_command_line=false
  show_command_line_only=false
  agent_conf_path="${base_dir}/${DEFAULT_CONF_REL_PATH}"

  if [ $# -eq 0 ]; then
    show_help >&2
    exit 1
  fi

  pass_options_to_agent=false
  log_level=INFO
  log_appender=DRFA
  java_debug=false
  java_debug_suspend=n
  log_dir="${base_dir}/log"

  agent_options=()

  while [[ $# -gt 0 ]]; do
    if $pass_options_to_agent; then
      agent_options+=( "$1" )
      shift
      continue
    fi

    case "$1" in
      --conf)
        agent_conf_path=$2
        if [ "${agent_conf_path:0:1}" != "/" ]; then
          # Convert to an absolute path
          agent_conf_path="$PWD/${agent_conf_path}"
        fi
        if [ ! -f "${agent_conf_path}" ]; then
          echo "Configuration file not found at ${agent_conf_path}" >&2
          exit 1
        fi
        shift
      ;;

      # Support --debug_log in addition to --debug-log for backward compatibility.
      --debug_log|--debug-log) log_level=DEBUG ;;

      # Support --debug_port in addition to --debug-port for backward compatibility.
      --debug_port|--debug-port)
        java_debug=true
        java_debug_port="$2"
        if [[ ! "${java_debug_port}" =~ ^[0-9]{1,5} ]] || \
           [ "${java_debug_port}" -gt 65535 ]; then
          echo "Invalid port number given to --debug_port: ${java_debug_port}" >&2
          exit 1
        fi
        shift
      ;;

      --debug-suspend) java_debug_suspend="y" ;;

      --pid-file) pid_file="$2"; shift ;;

      --show-command-line) show_command_line=true ;;

      --show-command-line-only)
        show_command_line=true
        show_command_line_only=true
      ;;

      -h|--help) show_help; exit 0 ;;
      --log_dir) log_dir=$2; shift ;;

      --) pass_options_to_agent=true ;;

      -*)
        echo "Unrecognized option: $1" >&2
        show_help >&2
        exit 1
      ;;

      *)
        if [ -z "${command}" ]; then
          command="$1"
        else
          echo "Only one command can be specified" >&2
          exit 1
        fi
      ;;
    esac
    shift
  done
}

is_pid_running() {
  kill -0 "$1" 2>/dev/null
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

write_pid_to_file() {
  mkdir -p $(dirname "${pid_file}")
  echo "$1" > "${pid_file}"
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
  if $daemonize; then
    if [ -n "${service_pid}" ]; then
      echo "${SERVICE_NAME} is already running (pid ${service_pid})"
    else
      stdout_file="${log_dir}"/csd-agent-server.out
      stderr_file="${log_dir}"/csd-agent-server.err
      "${java_cmd[@]}" >"${stdout_file}" 2>"${stderr_file}" </dev/null &
      service_pid=$!
      if wait_for_condition is_pid_running "${service_pid}"; then
        echo "${SERVICE_NAME} has started as ${service_pid}."
        write_pid_to_file "${service_pid}"
      else
        echo "${SERVICE_NAME} process ${service_pid} has failed to start." >&2
        echo "Please contact ClearStory Data support at support@clearstorydata.com." >&2
        exit 1
      fi
    fi
  else
    "${java_cmd[@]}"
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

kill_agent() {
  read_pid_file
  if [ -n "${service_pid}" ]; then
    echo "Killing ${SERVICE_NAME} (pid ${service_pid}) with SIGKILL"
    kill -SIGKILL "${service_pid}"
    rm -f "${pid_file}"
  else
    echo "${SERVICE_NAME} is not running"
  fi
}

# We are using /usr/bin/env because bash location may be different on different systems.
base_dir=$BASE_DIR

if [ -d "${base_dir}/target" ]; then
  # Development mode
  agent_jar_dir="${base_dir}/target"
  agent_server_jar_dir="${base_dir}/../csd-agent-server/target"
else
  # Production mode
  agent_jar_dir="${base_dir}/lib"
fi

agent_jar=""
for j in $(ls -t "${agent_jar_dir}"/csd-agent-core-*-shaded.jar); do
  if [ -f "${j}" ]; then
    agent_jar=${j}
    break
  fi
done

for j in $(ls -t "${agent_server_jar_dir}"/csd-agent-server-*-shaded.jar); do
  if [ -f "${j}" ]; then
    agent_jar="$agent_jar:${j}"
    break
  fi
done

if [ -z "${agent_jar}" ]; then
  echo "ClearStory Data Agent-Server jar file not found in ${agent_jar_dir}" >&2
  exit 1
fi

parse_args "$@"
mkdir -p "${log_dir}"

# Change directory so we can specify paths relative to the agent installation
# directory in the configuration.
cd "${base_dir}" || exit 1

if [ -z "${command}" ]; then
  echo "No command specified" >&2
  show_help >&2
  exit 1
fi

CLASSPATH="${agent_jar}"
export CLASSPATH

if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
  java_binary="${JAVA_HOME}/bin/java"
else
  java_binary=java
fi

java_version=$( "${java_binary}" -version 2>&1 | head -1)
java_version=${java_version#java version \"}
java_version=${java_version%\"}

if [ "${java_version}" == "1.7.0_51" ]; then
  cat >&2 <<-EOT

Java version ${java_version} is known to cause problems with ClearStory Data Agent-Server.
This incompatibility will be addresed in a future version of the agent-server.
The recommented Java version is 1.7.0_45. Please email support@clearstorydata.com
with any questions. We are sorry for the inconvenience.

EOT
  exit 1
fi

java_cmd=( "${java_binary}" ${CSD_AGENT_VM_ARGS:-} )

logback_conf_path="conf/logback.xml"  # relative to ${base_dir}
if [ ! -f "${logback_conf_path}" ]; then
  echo "The ${PWD}/${logback_conf_path} configuration file not found" >&2
  exit 1
fi

# See http://stackoverflow.com/questions/9156379/ora-01882-timezone-region-not-found
# for the explanation of "-Doracle.jdbc.timezoneAsRegion".
java_cmd+=(
  -Dlogback.configurationFile="${logback_conf_path}"
  -Dcsd.log.dir="${log_dir}"
  -Dcsd.log.appender="${log_appender}"
  -Dcsd.log.level="${log_level}"
  -Duser.timezone=PDT
)

if $java_debug; then
  java_cmd+=(
    -Xdebug
    -Xrunjdwp:transport=dt_socket,server=y,suspend=${java_debug_suspend},address=${java_debug_port}
  )
fi

java_cmd+=(
  com.clearstorydata.agent.server.AgentService
  server
  "${agent_conf_path}"
  "${agent_options[@]:+${agent_options[@]}}"
)

if $show_command_line; then
  echo "Agent-Server command line: ${java_cmd[@]}"
  echo "Classpath: ${CLASSPATH}"
fi

if $show_command_line_only; then
  exit
fi

if ! $daemonize && [ "${command}" != "start" ]; then
  echo 'Only the "start" command is supported with --no-daemon' >&2
  exit 1
fi

case "${command}" in
  start) start ;;
  stop) stop ;;
  kill) kill_agent ;;
  restart) stop && start ;;
  status)
    read_pid_file
    if [ -n "${service_pid}" ]; then
      echo "${SERVICE_NAME} is running (pid ${service_pid})"
    else
      echo "${SERVICE_NAME} is not running"
    fi
    ;;
  *)
    echo "Unknown command ${command}" >&2
    show_help >&2
    exit 1
esac
