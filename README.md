# devchain-container

> :warning: This repo is experimental and shouldn't be relied upon!

Docker container that runs:
- a single [Anoma](https://github.com/anoma/anoma) validator node against a preconfigured chain with a faucet
- a HTTP server serving a network release so that the chain can be joined with `anomac utils join-network`

## Prerequisites
- Docker
- Docker BuildKit

## Usage

```shell
# building the container may take a while and requires network access
# this default docker build command is fine if you just want to experiment with making transfers, etc.

# BASE_POINT should be an ancestor of COMMIT
export BASE_POINT='master'

# COMMIT must include the init-genesis-validator changes from https://github.com/anoma/anoma/pull/1053
# COMMIT must also be compatible with the `network-config.toml` in this repo
export COMMIT='b4021f085f0f692b07d150dd0929a6f5072cd9a4'

docker build \
    --build-arg BASE_POINT=${BASE_POINT} \
    --build-arg COMMIT=${COMMIT} \
    -t devchain-container .

# after build is done, start up a disposable container
# 8123 HTTP (used by anomac utils join-network)
# 26656 Tendermint P2P (not strictly necessary to expose)
# 26657 Tendermint RPC (used by anomac)
# -it - so the container can be killed by Ctrl+Cs
# --rm - makes the container disposable - don't use this --rm argument if you want to reuse a container and its chain!
docker run \
        -p 127.0.0.1:8123:8123 \
        -p 127.0.0.1:26656:26656 \
        -p 127.0.0.1:26657:26657 \
        -it \
        --rm \
            devchain-container
```

Once the container is running, go to http://localhost:8123 to determine what the chain ID is. eg if you see a file like `dev.b1ca22efbf6b78f06defa489e3.tar.gz`, then the chain ID is `dev.b1ca22efbf6b78f06defa489e3`. Chain ID may change on every docker build.

In another shell, while the container is still running:

```shell
export ANOMA_CHAIN_ID='dev.e49eb46d332bd37156fb503c5a'  # your chain ID here
export ANOMA_NETWORK_CONFIGS_SERVER='http://localhost:8123'
anomac utils join-network \
	--chain-id $ANOMA_CHAIN_ID
# there should now be a .anoma subdirectory in your present working directory

# briefly run anoman ledger once so that necessary wasms can be downloaded
# you should see output like "Downloading WASM ..."
# https://github.com/anoma/anoma/issues/1048
anoman ledger

# after this point, anomac should be able to interact with the chain as normal
# ie user guide from https://docs.anoma.net/user-guide/ledger.html#-initialize-an-account onwards
```
