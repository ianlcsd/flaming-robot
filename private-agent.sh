

case $1 in
start)
/Users/Ian1/workspace/csd-agent/csd-agent/csd-agent-core/bin/csd-agent.sh --debug-log --debug-port 8081 \
--conf /Users/Ian1/workspace/csd-agent/csd-agent/csd-agent-core/conf/local-dev-csd-agent-conf.json start
;;
*)
/Users/Ian1/workspace/csd-agent/csd-agent/csd-agent-core/bin/csd-agent.sh $1
esac
