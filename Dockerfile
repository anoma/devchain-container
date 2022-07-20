FROM ubuntu:jammy-20220531 AS base
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    clang-tools-14 \
    curl \
    git \
    libssl-dev \
    pkg-config && \
    rm -rf /var/lib/apt/lists/*
RUN groupadd -g 1000 builder && \
    useradd -r -m -u 1000 -g builder builder
RUN mkdir /usr/local/src/anoma && chown -R builder:builder /usr/local/src/anoma

USER builder

# recommended to use a nightly which has support for CARGO_UNSTABLE_SPARSE_REGISTRY for faster fetches
ARG RUSTUP_TOOLCHAIN="nightly-2022-06-24"
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain $RUSTUP_TOOLCHAIN
ENV PATH="/home/builder/.cargo/bin:${PATH}"

ARG CARGO_UNSTABLE_SPARSE_REGISTRY="true"
RUN cargo install cargo-chef --locked

RUN git clone --depth=1 https://github.com/anoma/anoma.git /usr/local/src/anoma
WORKDIR /usr/local/src/anoma

# BASE_POINT should be an ancestor of REF that shares the same toolchain
ARG BASE_POINT=v0.6.1
RUN git fetch --tags
RUN git fetch --depth=1 origin $BASE_POINT && git checkout $BASE_POINT
# actual nightly toolchain specified in repo is needed for running rustfmt in build.rs
# can be removed once https://github.com/anoma/namada/issues/40 is done
RUN rustup toolchain install $(cat rust-nightly-version)

RUN cargo fetch
RUN cargo chef prepare
RUN cargo chef cook \
    --no-default-features \
    --features "ABCI-plus-plus"
RUN git reset --hard

FROM base AS ref
ARG REF=v0.6.1
RUN git fetch --depth=1 origin $REF && git checkout $REF
# actual nightly toolchain specified in repo is needed for running rustfmt in build.rs
# can be removed once https://github.com/anoma/namada/issues/40 is done
RUN rustup toolchain install $(cat rust-nightly-version)

FROM ref as builder
RUN cargo fetch
RUN cargo chef prepare
RUN cargo chef cook \
    --no-default-features \
    --features "ABCI-plus-plus"
RUN git reset --hard
ENV RUSTFLAGS="-C strip=symbols"
RUN cargo build \
    --no-default-features \
    --features "ABCI-plus-plus ibc-vp" \
    --package anoma
RUN cargo build \
    --no-default-features \
    --features "ABCI-plus-plus" \
    --package anoma_apps \
    --bin anoma
RUN cargo build \
    --no-default-features \
    --features "ABCI-plus-plus" \
    --package anoma_apps \
    --bin anomaw
RUN cargo build \
    --no-default-features \
    --features "ABCI-plus-plus" \
    --package anoma_apps \
    --bin anomac
RUN cargo build \
    --no-default-features \
    --features "ABCI-plus-plus" \
    --package anoma_apps \
    --bin anoman

FROM ref AS tendermint-downloader
# TODO: fetch Tendermint according to version specified in repo, once https://github.com/anoma/namada/issues/153 is done
# TODO: make arm64 compatible as well
ARG TENDERMINT_URL='https://github.com/james-chf/github-builder/releases/download/tendermint-29e5fbcc648510e4763bd0af0b461aed92c21f30-linux-amd64/tendermint-linux-amd64'
RUN curl -L $TENDERMINT_URL > /tmp/tendermint++

FROM ref AS wasm-builder
RUN rustup target add wasm32-unknown-unknown
RUN make -C wasm/wasm_source
RUN make checksum-wasm

FROM ubuntu:jammy-20220531
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    curl \
    python3 \
    python3-pip \
    sudo && \
    apt-get clean

RUN pip3 install \
    toml==0.10.2 \
    toml-cli==0.3.1 \
    updog==1.4

COPY --from=tendermint-downloader --chmod=500 /tmp/tendermint++ /usr/local/bin
ENV TENDERMINT="tendermint++"
COPY --from=builder /usr/local/src/anoma/target/debug/anoma /usr/local/bin
COPY --from=builder /usr/local/src/anoma/target/debug/anomaw /usr/local/bin
COPY --from=builder /usr/local/src/anoma/target/debug/anomac /usr/local/bin
COPY --from=builder /usr/local/src/anoma/target/debug/anoman /usr/local/bin

WORKDIR /srv
COPY --from=wasm-builder /usr/local/src/anoma/wasm/checksums.json wasm/checksums.json
COPY --from=wasm-builder /usr/local/src/anoma/wasm/*.wasm wasm/

ENV ALIAS="validator-dev"
RUN anomac utils init-genesis-validator \
    --alias $ALIAS \
    --net-address 127.0.0.1:26656 \
    --unsafe-dont-encrypt

COPY --chmod=0755 add_validator_shard.py /usr/local/bin

COPY network-config.toml .
ARG ANOMA_NETWORK_CONFIG_PATH="network-config-processed.toml"
RUN add_validator_shard.py .anoma/pre-genesis/$ALIAS/validator.toml network-config.toml > $ANOMA_NETWORK_CONFIG_PATH

ARG ANOMA_CHAIN_PREFIX="dev"
RUN anomac utils init-network \
    --chain-prefix $ANOMA_CHAIN_PREFIX \
    --genesis-path $ANOMA_NETWORK_CONFIG_PATH \
    --wasm-checksums-path wasm/checksums.json \
    --unsafe-dont-encrypt && \
    rm -rf .anoma/$(basename *.tar.gz .tar.gz)

# TODO: it should eventually be possible to join a network using a local .tar.gz rather than via a download
RUN nohup bash -c "python3 -m http.server &" \
    && sleep 1 \
    && ANOMA_NETWORK_CONFIGS_SERVER='http://localhost:8000' anomac \
    utils join-network \
    --genesis-validator $ALIAS \
    --chain-id $(basename *.tar.gz .tar.gz)

RUN cp wasm/*.wasm .anoma/$(basename *.tar.gz .tar.gz)/wasm/

# ensure Tendermint RPC is exposed from within the container to the outside world
RUN toml set \
    --toml-path .anoma/$(basename *.tar.gz .tar.gz)/config.toml \
    ledger.tendermint.rpc_address 0.0.0.0:26657

ENV TM_LOG_LEVEL=warn
ENV ANOMA_LOG=debug
EXPOSE 8123 26656 26657
COPY run.sh .
CMD ["./run.sh"]