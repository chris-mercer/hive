#!/bin/bash

# Startup script to initialize and boot a fukuii instance.
#
# This script assumes the following files:
#  - fukuii distribution is at /opt/fukuii/
#  - `genesis.json` file is located in the filesystem root (mandatory)
#
# This script assumes the following environment variables:
#
#  - HIVE_BOOTNODE                enode URL of the remote bootstrap node
#  - HIVE_NETWORK_ID              network ID number to use for the eth protocol
#  - HIVE_CHAIN_ID                chain ID for EIP-155 replay protection
#  - HIVE_NODETYPE                sync and pruning selector (archive, full, light)
#
# Forks (mapped to ETC equivalents):
#
#  - HIVE_FORK_HOMESTEAD          homestead-block-number
#  - HIVE_FORK_TANGERINE          eip150-block-number
#  - HIVE_FORK_SPURIOUS           eip155-block-number + eip160-block-number
#  - HIVE_FORK_BYZANTIUM          atlantis-block-number (ETC Byzantium equivalent)
#  - HIVE_FORK_CONSTANTINOPLE     agharta-block-number (ETC Constantinople equivalent)
#  - HIVE_FORK_ISTANBUL           phoenix-block-number (ETC Istanbul equivalent)
#  - HIVE_FORK_BERLIN             magneto-block-number (ETC Berlin equivalent)
#  - HIVE_FORK_LONDON             mystique-block-number (ETC London partial)
#  - HIVE_SHANGHAI_TIMESTAMP      spiral-block-number (ETC Shanghai equivalent)
#
# Other:
#
#  - HIVE_MINER                   enable mining. value is coinbase address.
#  - HIVE_MINER_EXTRA             extra-data field to set for newly minted blocks
#  - HIVE_LOGLEVEL                client loglevel (0-5)

# Immediately abort the script on any error encountered
set -e

# Far-future block number for disabled forks
FAR_FUTURE="1000000000000000000"

# Default fork values (far-future = disabled)
HOMESTEAD=${HIVE_FORK_HOMESTEAD:-$FAR_FUTURE}
EIP150=${HIVE_FORK_TANGERINE:-$FAR_FUTURE}
EIP155=${HIVE_FORK_SPURIOUS:-$FAR_FUTURE}
EIP160=${HIVE_FORK_SPURIOUS:-$FAR_FUTURE}
ATLANTIS=${HIVE_FORK_BYZANTIUM:-$FAR_FUTURE}
AGHARTA=${HIVE_FORK_CONSTANTINOPLE:-$FAR_FUTURE}
PHOENIX=${HIVE_FORK_ISTANBUL:-$FAR_FUTURE}
MAGNETO=${HIVE_FORK_BERLIN:-$FAR_FUTURE}
MYSTIQUE=${HIVE_FORK_LONDON:-$FAR_FUTURE}
SPIRAL=${HIVE_SHANGHAI_TIMESTAMP:-$FAR_FUTURE}

# Network and chain ID
NETWORK_ID=${HIVE_NETWORK_ID:-1337}
if [ "$HIVE_CHAIN_ID" != "" ]; then
    CHAIN_ID_HEX=$(printf "0x%x" "$HIVE_CHAIN_ID")
else
    CHAIN_ID_HEX="0x539"
fi

# Configure the chain — strip config section from genesis, keep alloc/state.
mv /genesis.json /genesis-input.json
jq -f /mapper.jq /genesis-input.json > /genesis.json

# Dump genesis.
echo "Supplied genesis state:"
if [ "$HIVE_LOGLEVEL" != "" ] && [ "$HIVE_LOGLEVEL" -lt 4 ]; then
    jq 'del(.alloc[] | select(.balance == "0x123450000000000000000"))' /genesis.json
else
    cat /genesis.json
fi

# Mining configuration
MINING_ENABLED="false"
COINBASE="0000000000000000000000000000000000000000"
HEADER_EXTRA="fukuii"
if [ "$HIVE_MINER" != "" ]; then
    MINING_ENABLED="true"
    # Strip 0x prefix if present
    COINBASE=$(echo "$HIVE_MINER" | sed 's/^0x//')
fi
if [ "$HIVE_MINER_EXTRA" != "" ]; then
    HEADER_EXTRA="$HIVE_MINER_EXTRA"
fi

# Bootnode configuration
BOOTSTRAP_NODES="[]"
if [ "$HIVE_BOOTNODE" != "" ]; then
    BOOTSTRAP_NODES="[\"$HIVE_BOOTNODE\"]"
fi

# Configure logging level
LOG_LEVEL="INFO"
case "$HIVE_LOGLEVEL" in
    0|1) LOG_LEVEL="ERROR" ;;
    2)   LOG_LEVEL="WARN"  ;;
    3)   LOG_LEVEL="INFO"  ;;
    4)   LOG_LEVEL="DEBUG" ;;
    5)   LOG_LEVEL="TRACE" ;;
esac

# Generate the HOCON configuration file
cat > /hive.conf << HOCON_EOF
include required("file:///opt/fukuii/conf/fukuii.conf")

fukuii {
  datadir = "/tmp/fukuii-hive"

  blockchains {
    network = "test"
    test {
      network-id = $NETWORK_ID
      chain-id = "$CHAIN_ID_HEX"

      frontier-block-number = "0"
      homestead-block-number = "$HOMESTEAD"
      eip106-block-number = "$FAR_FUTURE"
      eip150-block-number = "$EIP150"
      eip155-block-number = "$EIP155"
      eip160-block-number = "$EIP160"
      eip161-block-number = "$FAR_FUTURE"

      difficulty-bomb-pause-block-number = "0"
      difficulty-bomb-continue-block-number = "0"
      difficulty-bomb-removal-block-number = "0"

      # ETH-only forks — always far-future on ETC
      byzantium-block-number = "$FAR_FUTURE"
      constantinople-block-number = "$FAR_FUTURE"
      petersburg-block-number = "$FAR_FUTURE"
      istanbul-block-number = "$FAR_FUTURE"
      berlin-block-number = "$FAR_FUTURE"
      muir-glacier-block-number = "$FAR_FUTURE"

      # ETC forks
      atlantis-block-number = "$ATLANTIS"
      agharta-block-number = "$AGHARTA"
      phoenix-block-number = "$PHOENIX"
      magneto-block-number = "$MAGNETO"
      mystique-block-number = "$MYSTIQUE"
      spiral-block-number = "$SPIRAL"
      olympia-block-number = "$FAR_FUTURE"

      ecip1099-block-number = "$FAR_FUTURE"

      dao = null

      account-start-nonce = "0"
      max-code-size = "24576"
      gas-tie-breaker = false
      eth-compatible-storage = true

      custom-genesis-file = { include required(file("/genesis.json")) }

      treasury-address = "0000000000000000000000000000000000000000"

      monetary-policy {
        first-era-block-reward = "5000000000000000000"
        first-era-reduced-block-reward = "5000000000000000000"
        first-era-constantinople-reduced-block-reward = "5000000000000000000"
        era-duration = 5000000
        reward-reduction-rate = 0.2
      }

      bootstrap-nodes = $BOOTSTRAP_NODES
      allowed-miners = []
    }
  }

  network {
    server-address {
      interface = "0.0.0.0"
      port = 9076
    }
    discovery {
      discovery-enabled = true
      interface = "0.0.0.0"
      port = 30303
    }
    rpc {
      http {
        mode = "http"
        enabled = true
        interface = "0.0.0.0"
        port = 8545
        cors-allowed-origins = ["*"]
      }
      apis = "eth,web3,net,personal,fukuii,debug,qa,admin"
    }
  }

  mining {
    mining-enabled = $MINING_ENABLED
    coinbase = "$COINBASE"
    header-extra-data = "$HEADER_EXTRA"
    protocol = pow
  }
}
HOCON_EOF

echo "Generated hive.conf:"
cat /hive.conf

# Get IP for NAT
ip=$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) || true

# Build JVM flags
JAVA_OPTS="-Xmx2g"
JAVA_OPTS="$JAVA_OPTS -Dconfig.file=/hive.conf"
JAVA_OPTS="$JAVA_OPTS -Dlogback.configurationFile=/opt/fukuii/conf/logback.xml"

export JAVA_OPTS

echo "Running fukuii with JAVA_OPTS=$JAVA_OPTS"
exec /opt/fukuii/bin/fukuii
