anvil_url := "http://127.0.0.1:8545"

private_key       := "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6"
# Fresh executor/utility addresses (not Anvil defaults, to avoid EIP-7702 delegations on Sepolia)
executor_addr     := "0x8dEe56a37D5d7E6dedcbf09865b42d4e8c4ae74a"
utility_addr      := "0xe567a07c0a9D289A26B20582B3c3c05b97e07492"

# Generate a state dump from Anvil with the Paymaster and 4337 accounts deployed
# for testing purposes.
generate-state-tornado:
    #!/usr/bin/env bash
    anvil --fork-url $SEPOLIA_RPC_URL --fork-block-number 10000000 --dump-state ./sdk/tests/fixtures/anvil-state.json --chain-id 31337 &
    ANVIL_PID=$!
    trap 'kill $ANVIL_PID 2>/dev/null' EXIT
    sleep 5

    PRIVATE_KEY={{private_key}} \
    forge script script/DeployPaymaster.s.sol \
        --fork-url {{anvil_url}} \
        --broadcast \
    
    STAKE_AMOUNT=1000000000000000000 \
    UNSTAKE_DELAY=3600 \
    DEPOSIT_AMOUNT=1000000000000000000 \
    PRIVATE_KEY={{private_key}} \
    forge script script/StakePaymaster.s.sol \
        --fork-url {{anvil_url}} \
        --broadcast

    PRIVATE_KEY={{private_key}} \
    forge script script/DeployTornado.s.sol \
        --fork-url {{anvil_url}} \
        --broadcast

    cast send --rpc-url {{anvil_url}} \
        --private-key {{private_key}} \
        {{executor_addr}} \
        --value 100ether

    cast send --rpc-url {{anvil_url}} \
        --private-key {{private_key}} \
        {{utility_addr}} \
        --value 100ether

