#!/usr/bin/env bash
#
# Script for initializing a Namada chain for local development and joining it. Note that this script trashes any
# existing `.namada` directory in the directory it is run!
#
# ## Prerequisites
# - bash
# - Python 3
# - toml Python pip library <https://pypi.org/project/toml/> (this is the `python3-toml` package on Ubuntu distributions)
# - trash CLI tool (`brew install trash` on macOS or `sudo apt-get install trash-cli` on Ubuntu)
#
# ## How to run
# This script should be run from the root of a Namada source code repo (<https://github.com/anoma/namada>). *.wasm files
# must already have been built and be present under the `wasm/` directory of the Namada repo. The only parameter for the
# shell script is the path to a network config toml compatible with the version of Namada being used. There are some
# example network configs under `network-configs/` in this repo. Example command:
#
# ```shell
# /path/to/repo/devchain-container/build_network.sh network-configs/mainline-v0.12.1.toml
# ````
#
# Once the script is finished, it should be possible to straight away start running a ledger node e.g. the command
# assuming binaries have been built is:
#
# ```shell
# target/debug/namadan ledger run
# ````

set -eoux pipefail
IFS=$'\n\t'

package() {
    # TODO: also clean up these files if the script is aborted or otherwise exits unsuccessfully
    trash ~/.local/share/namada || true
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
    $DEVCHAIN_CONTAINER_DIR/add_validator_shard.py ~/.local/share/namada/pre-genesis/$ALIAS/validator.toml $NETWORK_CONFIG_PATH >$NAMADA_NETWORK_CONFIG_PATH

    python3 wasm/checksums.py

    export NAMADA_CHAIN_PREFIX='local'

    target/debug/namadac utils init-network \
        --chain-prefix "$NAMADA_CHAIN_PREFIX" \
        --genesis-path "$NAMADA_NETWORK_CONFIG_PATH" \
        --wasm-checksums-path wasm/checksums.json \
        --unsafe-dont-encrypt

    basename *.tar.gz .tar.gz >${CHAIN_DIR}/chain-id
    export NAMADA_CHAIN_ID="$(cat ${CHAIN_DIR}/chain-id)"
    trash ~/.local/share/namada/${NAMADA_CHAIN_ID}
    mv "${NAMADA_CHAIN_ID}.tar.gz" $CHAIN_DIR

    export NAMADA_NETWORK_CONFIGS_SERVER='http://localhost:8123'
    nohup bash -c "python3 -m http.server --directory ${CHAIN_DIR} 8123 &" &&
        sleep 2 &&
        target/debug/namadac \
            utils join-network \
            --genesis-validator "$ALIAS" \
            --chain-id "${NAMADA_CHAIN_ID}" \
            --dont-prefetch-wasm

    cp wasm/*.wasm ~/.local/share/namada/${NAMADA_CHAIN_ID}/wasm/
    cp wasm/checksums.json ~/.local/share/namada/${NAMADA_CHAIN_ID}/wasm/

    tar -cvzf "${NAMADA_CHAIN_ID}.prebuilt.tar.gz" ~/.local/share/namada
    mv "${NAMADA_CHAIN_ID}.prebuilt.tar.gz" $CHAIN_DIR

    # TODO: also clean up these files if the script is aborted or otherwise exits unsuccessfully
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
