#!/usr/bin/env bash
set -eoux pipefail
IFS=$'\n\t'

python3 wasm/checksums.py
# TODO: only try to initialize network on first run
namadac utils init-network \
    --chain-prefix "$NAMADA_CHAIN_PREFIX" \
    --genesis-path "$NAMADA_NETWORK_CONFIG_PATH" \
    --wasm-checksums-path wasm/checksums.json \
    --unsafe-dont-encrypt &&
    rm -rf .namada/"$(basename *.tar.gz .tar.gz)"

basename *.tar.gz .tar.gz >chain-id
