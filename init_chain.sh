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

basename *.tar.gz .tar.gz >chain-id
