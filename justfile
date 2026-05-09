anvil_url := "http://127.0.0.1:8545"

factory := "0x0227628f3F023bb0B980b67D528571c95c6DaC1c"  # sepolia UniV3 factory

entry_point  := "0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108"
paymaster_addr    := "0x2C6ddd76DD36CDdE9CB967a8ae66767b456EB1Ba"
private_key       := "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6"
# Fresh executor/utility addresses (not Anvil defaults, to avoid EIP-7702 delegations on Sepolia)
executor_addr     := "0x8dEe56a37D5d7E6dedcbf09865b42d4e8c4ae74a"
utility_addr      := "0xe567a07c0a9D289A26B20582B3c3c05b97e07492"

weth := "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"

# Sepolia TC 1 ETH instance.
tornado_addr := "0x8cc930096B4Df705A007c4A039BDFA1320Ed2508"

# Sepolia RailgunSmartWallet proxy
railgun_smart_wallet_addr := "0xeCFCf3b4eC647c4Ca6D49108b311b7a7C9543fea"
# Railgun Master Public Key
railgun_master_public_key := "0x19acdde26147205d58fd7768be7c011f08a147ef86e6b70968d09c81cef74b13"

# Generate a state dump from Anvil with the Paymaster and 4337 accounts deployed
# for testing purposes.
generate-state-tornado:
    #!/usr/bin/env bash
    anvil --fork-url $SEPOLIA_RPC_URL --fork-block-number 10000000 --dump-state ./sdk/tests/fixtures/anvil-state.json --chain-id 31337 &
    ANVIL_PID=$!
    trap 'kill $ANVIL_PID 2>/dev/null' EXIT
    sleep 5

    ENTRY_POINT={{entry_point}} \
    WETH={{weth}} \
    FACTORY={{factory}} \
    TWAP_PERIOD=0 \
    PRIVATE_KEY={{private_key}} \
    forge script script/DeployPaymaster.s.sol \
        --fork-url {{anvil_url}} \
        --broadcast \
    
    PAYMASTER={{paymaster_addr}} \
    STAKE_AMOUNT=1000000000000000000 \
    UNSTAKE_DELAY=3600 \
    DEPOSIT_AMOUNT=1000000000000000000 \
    TORNADO_INSTANCE={{tornado_addr}} \
    PRIVATE_KEY={{private_key}} \
    forge script script/StakePaymaster.s.sol \
        --fork-url {{anvil_url}} \
        --broadcast

    PAYMASTER={{paymaster_addr}} \
    TORNADO_INSTANCE={{tornado_addr}} \
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

# Generate a state dump from Anvil with the Paymaster and 4337 accounts deployed
# for testing purposes.
generate-state-railgun:
    #!/usr/bin/env bash
    anvil --fork-url $SEPOLIA_RPC_URL --fork-block-number 10000000 --dump-state ./sdk/tests/fixtures/anvil-state-railgun.json --chain-id 31337 &
    ANVIL_PID=$!
    trap 'kill $ANVIL_PID 2>/dev/null' EXIT
    sleep 5

    ENTRY_POINT={{entry_point}} \
    WETH={{weth}} \
    FACTORY={{factory}} \
    TWAP_PERIOD=0 \
    PRIVATE_KEY={{private_key}} \
    forge script script/DeployPaymaster.s.sol \
        --fork-url {{anvil_url}} \
        --broadcast \
    
    PAYMASTER={{paymaster_addr}} \
    STAKE_AMOUNT=1000000000000000000 \
    UNSTAKE_DELAY=3600 \
    DEPOSIT_AMOUNT=1000000000000000000 \
    TORNADO_INSTANCE={{tornado_addr}} \
    PRIVATE_KEY={{private_key}} \
    forge script script/StakePaymaster.s.sol \
        --fork-url {{anvil_url}} \
        --broadcast

    PAYMASTER={{paymaster_addr}} \
    RAILGUN_SMART_WALLET={{railgun_smart_wallet_addr}} \
    MASTER_PUBLIC_KEY={{railgun_master_public_key}} \
    PRIVATE_KEY={{private_key}} \
    forge script script/DeployRailgun.s.sol \
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
