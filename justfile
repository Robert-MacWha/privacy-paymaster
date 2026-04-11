anvil_url := "http://localhost:8545"
alto_url  := "http://localhost:4337"

entry_point  := "0x433709009B8330FDa32311DF1C2AFA402eD8D009"
tornado_addr := "0x8cc930096B4Df705A007c4A039BDFA1320Ed2508"
commitment   := "0x1291259ce38518ac740a92829a0c40c0928398db467fa1f2a90776d360cab1ee"

deployer_pk       := "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6"
deployer_addr     := "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720"
paymaster_addr    := "YOUR_PAYMASTER_ADDR"
tornado_acct_addr := "YOUR_TORNADO_ACCOUNT_ADDR"

# Anvil default funded key (used for funding and cast sends)
executor_key := "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

dev:
    #!/usr/bin/env bash
    trap 'kill 0' EXIT
    just anvil &
    sleep 2
    just alto

# Deploy contracts + wire test state against a running anvil fork.
# Run this once after `just anvil` before executing the TypeScript E2E test.
setup-e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    # Fund deployer (it has no ETH on the Sepolia fork)
    cast send --rpc-url {{anvil_url}} --private-key {{executor_key}} \
        {{deployer_addr}} --value 1ether
    # Deploy PrivacyPaymaster (nonce 0 → paymaster_addr) and TornadoAccount
    # (nonce 1 → tornado_acct_addr). Deployer == PAYMASTER_OWNER so the script
    # also calls setApprovedSender automatically.
    ENTRY_POINT={{entry_point}} \
    TORNADO_INSTANCE={{tornado_addr}} \
    PAYMASTER_OWNER={{deployer_addr}} \
    DEPLOYER_PK={{deployer_pk}} \
    WETH=0x0000000000000000000000000000000000000000 \
    STATIC_ORACLE=0x0000000000000000000000000000000000000000 \
    TWAP_PERIOD=0 \
    forge script contracts/script/DeployPrivacy.s.sol \
        --rpc-url {{anvil_url}} --broadcast
    # Fund paymaster's EntryPoint deposit
    cast send --rpc-url {{anvil_url}} --private-key {{executor_key}} \
        --value 1ether {{entry_point}} "depositTo(address)" {{paymaster_addr}}
    # Plant the tornado deposit that the snapshot proofs verify against
    cast send --rpc-url {{anvil_url}} --private-key {{executor_key}} \
        --value 1ether {{tornado_addr}} "deposit(bytes32)" {{commitment}}

# Start services, deploy, and run the TypeScript E2E suite end-to-end.
e2e:
    #!/usr/bin/env bash
    trap 'kill 0' EXIT
    just anvil &
    sleep 2
    just alto &
    sleep 2
    just setup-e2e
    cd sdk && bun test

anvil:
    anvil --fork-url $SEPOLIA_RPC_URL --fork-block-number 10000000

alto:
    bunx @pimlico/alto \
        --entrypoints {{entry_point}} \
        --executor-private-keys {{executor_key}} \
        --utility-private-key {{executor_key}} \
        --min-entity-stake 1 \
        --min-entity-unstake-delay 1 \
        --rpc-url {{anvil_url}} \
        --port 4337
