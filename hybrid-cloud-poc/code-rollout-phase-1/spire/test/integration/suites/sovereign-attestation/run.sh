#!/bin/bash

set -ex

# build the server and agent with the unified_identity tag
go build -tags unified_identity -o ../../../bin/spire-server ../../../cmd/spire-server
go build -tags unified_identity -o ../../../bin/spire-agent ../../../cmd/spire-agent

# build the client
go build -tags unified_identity -o ../../../bin/sovereign-attestation ../setup/sovereign-attestation

# start the server
../../../bin/spire-server run -config conf/server.conf &

# wait for the server to be ready
sleep 5

# start the agent
../../../bin/spire-agent run -config conf/agent.conf &

# wait for the agent to be ready
sleep 5

# run the client
../../../bin/sovereign-attestation

# stop the agent
kill %2

# stop the server
kill %1
