FROM ubuntu:22.04 AS builder
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
ENV RUSTUP_TOOLCHAIN="nightly-2022-06-14"
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain $RUSTUP_TOOLCHAIN
RUN /home/builder/.cargo/bin/cargo install cargo-chef --locked

RUN git clone --depth=1 https://github.com/anoma/anoma.git /usr/local/src/anoma
WORKDIR /usr/local/src/anoma

# base point should be an ancestor of commit
ARG BASE_POINT=v0.6.0
RUN git fetch --tags
RUN git fetch --depth=1 origin $BASE_POINT && git checkout $BASE_POINT
# warm up toolchain and likely dependencies
RUN /home/builder/.cargo/bin/cargo
RUN /home/builder/.cargo/bin/cargo chef prepare
RUN /home/builder/.cargo/bin/cargo chef cook
RUN git reset --hard

ARG REF=v0.6.0
RUN git fetch --depth=1 origin $REF && git checkout $REF
RUN /home/builder/.cargo/bin/cargo chef prepare
RUN /home/builder/.cargo/bin/cargo chef cook
RUN git reset --hard

RUN /home/builder/.cargo/bin/cargo build \
    --package anoma_apps \
    --bin anoma
RUN /home/builder/.cargo/bin/cargo build \
    --package anoma_apps \
    --bin anomaw
RUN /home/builder/.cargo/bin/cargo build \
    --package anoma_apps \
    --bin anomac
RUN /home/builder/.cargo/bin/cargo build \
    --package anoma_apps \
    --bin anoman

FROM ubuntu:22.04
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

COPY --from=builder /usr/local/src/anoma/scripts/install/get_tendermint.sh /usr/local/bin
RUN get_tendermint.sh

COPY --from=builder /usr/local/src/anoma/target/debug/anoma /usr/local/bin
COPY --from=builder /usr/local/src/anoma/target/debug/anomaw /usr/local/bin
COPY --from=builder /usr/local/src/anoma/target/debug/anomac /usr/local/bin
COPY --from=builder /usr/local/src/anoma/target/debug/anoman /usr/local/bin

WORKDIR /srv
COPY --from=builder /usr/local/src/anoma/wasm/checksums.json wasm/checksums.json

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

RUN nohup bash -c "python3 -m http.server &" \
    && sleep 1 \
    && ANOMA_NETWORK_CONFIGS_SERVER='http://localhost:8000' anomac \
    utils join-network \
    --genesis-validator $ALIAS \
    --chain-id $(basename *.tar.gz .tar.gz)

# download wasms
RUN timeout 10s anoman ledger || true
# ensure Tendermint RPC is exposed from within the container to the outside world
RUN toml set \
    --toml-path .anoma/$(basename *.tar.gz .tar.gz)/config.toml \
    ledger.tendermint.rpc_address 0.0.0.0:26657

ENV TM_LOG_LEVEL=none
ENV ANOMA_LOG=debug
EXPOSE 8123 26656 26657
COPY run.sh .
CMD ["./run.sh"]