# devchain-container

> :warning: This repo is experimental and shouldn't be relied upon!

Docker container that runs:

- a single [Anoma](https://github.com/anoma/anoma) validator node against a preconfigured chain with a faucet
- a HTTP server serving a network release so that the chain can be joined with `anomac utils join-network`

## Prerequisites

- Docker
- Docker BuildKit
- Docker Compose

## Building and running the ledger container

### Using Docker Compose (recommended)

Run `docker compose up` to build and run the ledger Docker container. See `docker-compose.yml` for more details if interested. The container will be reused by default, run `docker compose down` to use a fresh container if desired.

### Manually

```shell
# building the container may take a while and requires network access
# this default docker build command is fine if you just want to experiment with making transfers, etc.

# REF is the git commit or tag you want to build anoma from
# it must be at least anoma v0.6.0 or a later commit
# REF must also be compatible with the `network-config.toml` in this repo (until https://github.com/anoma/anoma/issues/1105 is done, at which point we could use some pre-provided network config template)
export REF='v0.6.1'

# BASE_POINT is built before REF, it should preferably share code and crate dependencies with REF, to help with caching
export BASE_POINT='v0.6.1'

docker build \
    --build-arg BASE_POINT=${BASE_POINT} \
    --build-arg REF=${REF} \
    -t devchain-container:${REF} \
    -t dev-container .

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

## Joining the devchain

Once the container is running, go to <http://localhost:8123> to determine what the chain ID is. eg if you see a file like `dev.b1ca22efbf6b78f06defa489e3.tar.gz`, then the chain ID is `dev.b1ca22efbf6b78f06defa489e3`. Chain ID will change on every `docker build`, but will be the same for different `docker run`s as long as the same image is being used.

In another shell, while the container is still running:

```shell
export ANOMA_CHAIN_ID='dev.e49eb46d332bd37156fb503c5a'  # your chain ID here
export ANOMA_NETWORK_CONFIGS_SERVER='http://localhost:8123'
anomac utils join-network \
 --chain-id $ANOMA_CHAIN_ID
# there should now be a .anoma subdirectory in your present working directory

# briefly run anoman ledger once so that necessary wasms can be downloaded
# you should see output like "Downloading WASM ..."
# until https://github.com/anoma/anoma/issues/1048 is fixed this is needed
anoman ledger
```

After this point, `anomac` should ideally be able to interact with the chain as if it were a regular testnet. i.e. the user guide from <https://docs.anoma.net/user-guide/ledger.html#-initialize-an-account> onwards should be followable.
