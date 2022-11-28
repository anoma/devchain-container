# devchain-container

> :warning: This repo is experimental and shouldn't be relied upon!

Docker container that runs:

- a single [Namada](https://github.com/anoma/namada) validator node for a preconfigured chain with a faucet
- a HTTP server serving a network release so that a chain configuration can be downloaded

## Prerequisites

- Docker
- Docker BuildKit
- Docker Compose

## Running the ledger via Docker

### Using Docker Compose (recommended)

Run `docker compose up` to build and run the ledger Docker container. See `docker-compose.yml` for more details if interested. The container will be reused by default, run `docker compose down` to use a fresh container if desired.

### Manually

```shell
# building the container may take a while and requires network access
# this default docker build command is fine if you just want to experiment with making transfers, etc.

# REF is the git commit or tag you want to build namada from
# it must be at least this version or a later commit
# REF must also be compatible with the `network-config.toml` in this repo (until https://github.com/anoma/anoma/issues/1105 is done, at which point we could use some pre-provided network config template)
export REF='v0.10.1'

# BASE_POINT is built before REF, it should preferably share code and crate dependencies with REF, to help with caching
export BASE_POINT='v0.10.1'

docker build \
    --build-arg BASE_POINT=${BASE_POINT} \
    --build-arg REF=${REF} \
    -t devchain-container:${REF} \
    -t dev-container .

# after build is done, start up a disposable container
# 8123 HTTP (used by namadac utils join-network)
# 26656 Tendermint P2P (not strictly necessary to expose)
# 26657 Tendermint RPC (used by namadac)
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

## Running the ledger natively

Start the Docker container as above, then go to <http://localhost:8123> and download the `prebuilt.tar.gz` archive. Extract it, and there should be a `.anoma` directory inside it. The Docker container can now be stopped.

It should be possible to run `namada` commands from inside whatever directory contains this `.anoma` directory, and the `namada` commands will be configured to use this preconfigured chain. e.g. `namadan ledger run` could start up a validator node for this chain.
