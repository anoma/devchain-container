#!/usr/bin/env bash
# run in a namada repo, with binaries built, to build a prebuilt archive
# ensure wasms are already built!
# for namada v0.11+

# NB: MAKE SURE PYTHON CAN ACCEPT NETWORK CONNECTIONS BEFORE RUNNING THIS SCRIPT!
set -eoux pipefail
IFS=$'\n\t'

package() {
    # TODO: clean up on abort
    trash .namada || true
    git checkout --ours -- wasm/checksums.json
    trash nohup.out || true

    export CHAIN_DIR='.hack/chains'
    mkdir -p $CHAIN_DIR

    export NETWORK_CONFIG_PATH=$1
    export ALIAS='validator-local-dev'

    target/debug/namadac utils init-genesis-validator \
        --alias $ALIAS \
        --net-address 127.0.0.1:26656 \
        --commission-rate 0.1 \
        --max-commission-rate-change 0.1 \
        --unsafe-dont-encrypt

    # get the directory of this script
    export DEVCHAIN_CONTAINER_DIR="$(dirname $0)"
    export NAMADA_NETWORK_CONFIG_PATH="${CHAIN_DIR}/network-config-processed.toml"
    $DEVCHAIN_CONTAINER_DIR/add_validator_shard.py .namada/pre-genesis/$ALIAS/validator.toml $NETWORK_CONFIG_PATH >$NAMADA_NETWORK_CONFIG_PATH

    python3 wasm/checksums.py

    export NAMADA_CHAIN_PREFIX='local'

    target/debug/namadac utils init-network \
        --chain-prefix "$NAMADA_CHAIN_PREFIX" \
        --genesis-path "$NAMADA_NETWORK_CONFIG_PATH" \
        --wasm-checksums-path wasm/checksums.json \
        --unsafe-dont-encrypt

    basename *.tar.gz .tar.gz >${CHAIN_DIR}/chain-id
    export NAMADA_CHAIN_ID="$(cat ${CHAIN_DIR}/chain-id)"
    trash ".namada/${NAMADA_CHAIN_ID}"
    mv "${NAMADA_CHAIN_ID}.tar.gz" $CHAIN_DIR

    export NAMADA_NETWORK_CONFIGS_SERVER='http://localhost:8123'
    nohup bash -c "python3 -m http.server --directory ${CHAIN_DIR} 8123 &" &&
        sleep 2 &&
        target/debug/namadac \
            utils join-network \
            --genesis-validator "$ALIAS" \
            --chain-id "${NAMADA_CHAIN_ID}" \
            --dont-prefetch-wasm

    cp wasm/*.wasm ".namada/${NAMADA_CHAIN_ID}/wasm/"
    cp wasm/checksums.json ".namada/${NAMADA_CHAIN_ID}/wasm/"

    tar -cvzf "${NAMADA_CHAIN_ID}.prebuilt.tar.gz" .namada
    mv "${NAMADA_CHAIN_ID}.prebuilt.tar.gz" $CHAIN_DIR

    # TODO: clean up on abort
    git checkout --ours -- wasm/checksums.json
    trash nohup.out

    # don't trash anoma - so we're ready to go with the chain
    echo "Run the ledger!"
}

main() {
    set -x

    package $@

    set +x
}

main $@
