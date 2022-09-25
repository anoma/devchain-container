FROM ubuntu:jammy-20220815 AS base
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
RUN mkdir /usr/local/src/namada && chown -R builder:builder /usr/local/src/namada

USER builder

ENV RUSTFLAGS="-C strip=symbols"

# recommended to use a nightly which has support for CARGO_UNSTABLE_SPARSE_REGISTRY for faster fetches
ARG RUSTUP_TOOLCHAIN="nightly-2022-09-25"
ARG CARGO_UNSTABLE_SPARSE_REGISTRY="true"

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain $RUSTUP_TOOLCHAIN
ENV PATH="/home/builder/.cargo/bin:${PATH}"
RUN cargo install cargo-chef --locked

RUN git clone --depth=1 https://github.com/anoma/namada.git /usr/local/src/namada
WORKDIR /usr/local/src/namada

# BASE_POINT should be an ancestor of REF that shares the same toolchain
ARG BASE_POINT=v0.7.1
RUN git fetch --tags
RUN git fetch --depth=1 origin $BASE_POINT && git checkout $BASE_POINT
# actual nightly toolchain specified in repo is needed for running rustfmt in build.rs
# can be removed once https://github.com/anoma/namada/issues/40 is done
RUN rustup toolchain install "$(cat rust-nightly-version)"

RUN cargo fetch
RUN cargo chef prepare
ARG ANOMA_BASE_FFLAGS="default"
RUN cargo chef cook \
    --no-default-features \
    --features "$ANOMA_BASE_FFLAGS"
RUN git reset --hard

FROM base AS ref
ARG REF=v0.7.1
RUN git fetch --depth=1 origin $REF && git checkout $REF
# actual nightly toolchain specified in repo is needed for running rustfmt in build.rs
# can be removed once https://github.com/anoma/namada/issues/40 is done
RUN rustup toolchain install "$(cat rust-nightly-version)"

FROM ref as builder
RUN cargo fetch
RUN cargo chef prepare
ARG ANOMA_REF_FFLAGS="default"
RUN cargo chef cook \
    --no-default-features \
    --features "$ANOMA_REF_FFLAGS"
RUN git reset --hard
RUN cargo build \
    --no-default-features \
    --features "$ANOMA_REF_FFLAGS" \
    --package namada_apps \
    --bin namada
RUN cargo build \
    --no-default-features \
    --features "$ANOMA_REF_FFLAGS" \
    --package namada_apps \
    --bin namadaw
RUN cargo build \
    --no-default-features \
    --features "$ANOMA_REF_FFLAGS" \
    --package namada_apps \
    --bin namadac
RUN cargo build \
    --no-default-features \
    --features "$ANOMA_REF_FFLAGS" \
    --package namada_apps \
    --bin namadan

FROM ref AS tendermint-downloader
# TODO: fetch Tendermint according to version specified in repo, once https://github.com/anoma/namada/issues/153 is done
# TODO: make arm64 compatible as well
ARG TENDERMINT_URL='https://github.com/heliaxdev/tendermint/releases/download/v0.1.1-abcipp/tendermint_0.1.1-abcipp_linux_amd64.tar.gz'
RUN curl -L $TENDERMINT_URL > /tmp/tendermint.tar.gz && cd /tmp && tar -xzvf tendermint.tar.gz

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

RUN pip3 install --no-cache-dir \
    toml==0.10.2 \
    toml-cli==0.3.1 \
    updog==1.4

# pre-emptively downloading geth as it is needed by Ethereum bridge branches
RUN curl -L https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.10.20-8f2416a8.tar.gz --output /tmp/geth.tgz && \
    tar -xzvf /tmp/geth.tgz -C /tmp && \
    cp /tmp/geth-linux-amd64-1.10.20-8f2416a8/geth /usr/local/bin/ && \
    chmod a+x /usr/local/bin/geth && \
    rm /tmp/geth.tgz

COPY --from=tendermint-downloader --chmod=500 /tmp/tendermint /usr/local/bin
COPY --from=builder /usr/local/src/namada/target/debug/namada /usr/local/bin
COPY --from=builder /usr/local/src/namada/target/debug/namadaw /usr/local/bin
COPY --from=builder /usr/local/src/namada/target/debug/namadac /usr/local/bin
COPY --from=builder /usr/local/src/namada/target/debug/namadan /usr/local/bin

WORKDIR /srv
COPY --from=wasm-builder /usr/local/src/namada/wasm/checksums.py wasm/checksums.py
COPY --from=wasm-builder /usr/local/src/namada/wasm/*.wasm wasm/

ENV ALIAS="validator-dev"
RUN namadac utils init-genesis-validator \
    --alias $ALIAS \
    --net-address 127.0.0.1:26656 \
    --unsafe-dont-encrypt

COPY --chmod=0755 add_validator_shard.py /usr/local/bin

COPY network-config.toml .
ENV ANOMA_NETWORK_CONFIG_PATH="network-config-processed.toml"
RUN add_validator_shard.py .anoma/pre-genesis/$ALIAS/validator.toml network-config.toml > $ANOMA_NETWORK_CONFIG_PATH

ENV ANOMA_CHAIN_PREFIX="dev"
ENV TM_LOG_LEVEL=warn
ENV ANOMA_LOG=debug
EXPOSE 8123 26656 26657
COPY init_chain.sh .
COPY run.sh .
CMD ["./run.sh"]