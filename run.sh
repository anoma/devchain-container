#!/usr/bin/env bash
set -eoux pipefail
IFS=$'\n\t'

# run init_chain.sh only if chain-id file is not present
if [ ! -f chain-id ]; then
    echo "chain-id file not found, running init_chain.sh"
    ./init_chain.sh
else
    echo "chain-id file found ($(cat chain-id)), skipping init_chain.sh"
fi

if [ ! -d ".namada/$(cat chain-id)" ]; then
    echo "couldn't find .namada/($(cat chain-id)) dir, will join chain"
    # TODO: it should eventually be possible to join a network using a local .tar.gz rather than via a download
    nohup bash -c "python3 -m http.server &" &&
        sleep 1 &&
        NAMADA_NETWORK_CONFIGS_SERVER='http://localhost:8000' namadac \
            utils join-network \
            --genesis-validator "$ALIAS" \
            --chain-id "$(cat chain-id)" \
            --dont-prefetch-wasm

    cp wasm/*.wasm ".namada/$(cat chain-id)/wasm/"
    cp wasm/checksums.json ".namada/$(cat chain-id)/wasm/"

    # package up and serve the built .namada directory for users who want to run a ledger outside of the container
    tar -cvzf "prebuilt.tar.gz" .namada
else
    echo "found .namada/$(cat chain-id) dir, so chain is already joined"
fi

declare -a PIDS=()

updog -p 8123 &
PIDS[0]=$!

namadan ledger &
PIDS[1]=$!

trap 'kill ${PIDS[0]} ${PIDS[1]}; exit 0' INT
wait
