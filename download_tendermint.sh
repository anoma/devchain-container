#!/usr/bin/env bash
# downloads the correct Tendermint binary to /tmp/tendermint
set -eoux pipefail
IFS=$'\n\t'

# TODO: fetch Tendermint according to version specified in repo, once https://github.com/anoma/namada/issues/153 is done
main() {
    ARCH="$(python3 -c "print('${TARGETPLATFORM:-linux/amd64}'.split('/')[1])")"
    readonly ARCH

    if [ "${ARCH}" = "arm64" ]; then
        TENDERMINT_URL="${TENDERMINT_ARM64_URL}"
    elif [ "${ARCH}" = "amd64" ]; then
        TENDERMINT_URL="${TENDERMINT_AMD64_URL}"
    else
        echo "Unsupported architecture: $ARCH"
        exit 1
    fi
    echo "Downloading from ${TENDERMINT_URL}..."
    curl -L "${TENDERMINT_URL}" >/tmp/tendermint.tar.gz
    cd /tmp
    tar -xzvf tendermint.tar.gz

    TENDERMINT_VERSION=$(/tmp/tendermint version)
    readonly TENDERMINT_VERSION
    echo "Downloaded Tendermint version ${TENDERMINT_VERSION}"
}

main
