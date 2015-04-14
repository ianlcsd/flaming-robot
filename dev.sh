AMQ_CMD=/opt/apache-activemq-5.10.0-csd-1/bin/macosx/activemq
AGENT_SERVER_CMD=~/bin/agent-server.sh
PRIVATE_AGENT_CMD=~/workspace/csd-agent/csd-agent/csd-agent-core/bin/csd-agent.sh
STORY_WEB_CMD=~/bin/story-web.sh

start() {
  ## amq
  echo "***************************"
  $AMQ_CMD start

  ## agent-sever
  echo "***************************"
  $AGENT_SERVER_CMD \
    --debug-log --debug-port 8082 \
    --conf conf/local-dev-agent-server-config.yml start

  ## private-agent
  echo "***************************"
  $PRIVATE_AGENT_CMD \
    --debug-log --debug-port 8081 \
    --conf /Users/Ian1/bin/conf/local-dev-csd-agent-conf.json start
  ## story-web
  echo "***************************"
  $STORY_WEB_CMD start

  echo "***************************"
}

stop() {
  echo "***************************"
  $STORY_WEB_CMD  stop

  echo "***************************"
  $PRIVATE_AGENT_CMD stop

  echo "***************************"
  $AGENT_SERVER_CMD stop

  echo "***************************"
  $AMQ_CMD stop

  echo "***************************"
}

restart() {
  stop
  start
}

status() {
  echo "***************************"
  $STORY_WEB_CMD  status
  echo "***************************"
  $PRIVATE_AGENT_CMD status
  echo "***************************"
  $AGENT_SERVER_CMD status
  echo "***************************"
  $AMQ_CMD status
  echo "***************************"

}

case $1 in
start) start ;;
stop) stop ;;
restart) restart ;;
status) status ;;
esac
