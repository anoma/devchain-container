#!/usr/bin/env bash
set -eoux pipefail
IFS=$'\n\t'

# TODO: only try to initialize network on first run
namadac utils init-network \
    --chain-prefix "$ANOMA_CHAIN_PREFIX" \
    --genesis-path "$ANOMA_NETWORK_CONFIG_PATH" \
    --wasm-checksums-path wasm/checksums.json \
    --unsafe-dont-encrypt &&
    rm -rf .anoma/"$(basename *.tar.gz .tar.gz)"

# TODO: it should eventually be possible to join a network using a local .tar.gz rather than via a download
nohup bash -c "python3 -m http.server &" &&
    sleep 1 &&
    ANOMA_NETWORK_CONFIGS_SERVER='http://localhost:8000' namadac \
        utils join-network \
        --genesis-validator "$ALIAS" \
        --chain-id "$(basename *.tar.gz .tar.gz)"

cp wasm/*.wasm ".anoma/$(basename *.tar.gz .tar.gz)/wasm/"
cp wasm/checksums.json ".anoma/$(basename *.tar.gz .tar.gz)/wasm/"

# ensure Tendermint RPC is exposed from within the container to the outside world
toml set \
    --toml-path ".anoma/$(basename *.tar.gz .tar.gz)/config.toml" \
    ledger.tendermint.rpc_address 0.0.0.0:26657

# package up and serve the built .anoma directory for users who want to run a ledger outside of the container
tar -cvzf "anoma-$(basename *.tar.gz .tar.gz).tar.gz" .anoma

updog -p 8123 &

namadan ledger &

wait -n

exit $?
