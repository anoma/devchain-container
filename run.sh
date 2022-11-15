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

# TODO: it should eventually be possible to join a network using a local .tar.gz rather than via a download
nohup bash -c "python3 -m http.server &" &&
    sleep 1 &&
    ANOMA_NETWORK_CONFIGS_SERVER='http://localhost:8000' namadac \
        utils join-network \
        --genesis-validator "$ALIAS" \
        --chain-id "$(cat chain-id)" \
        --dont-prefetch-wasm

cp wasm/*.wasm ".anoma/$(cat chain-id)/wasm/"
cp wasm/checksums.json ".anoma/$(cat chain-id)/wasm/"

# ensure Tendermint RPC is exposed from within the container to the outside world
toml set \
    --toml-path ".anoma/$(cat chain-id)/config.toml" \
    ledger.tendermint.rpc_address 0.0.0.0:26657

# package up and serve the built .anoma directory for users who want to run a ledger outside of the container
tar -cvzf "prebuilt.tar.gz" .anoma

updog -p 8123 &

namadan ledger &

wait -n

exit $?
