# Leftover Funds

## Status
Obsolete

Attack was previously possible when using a singleton `sender` contract. Because of this we decided to switch to using 7702-delegated EOAs as senders, which eliminates the attack vector because each user has their own sender which only they can call functions on / from.

## Threat
Using a singleton `sender` account, users can leave leftover funds in the `sender` after a transaction completes. Since anyone can call functions on the `sender` via tail calls, any funds left in `sender` can be stolen by attackers.

## Example Attack Scenario
1. User unshields WETH from tornadocash into `sender`
2. User swaps WETH for ETH on a DEX via a tail call
   1. Due to a DEX price change, the user receives more ETH than expected.
3. User withdraws ETH from `sender` to their EOA
   1. The unexpected extra ETH isn't withdrawn and remains in `sender`
4. Attacker backruns the user's transaction and withdraws the leftover ETH from `sender` to their own EOA.

This attack already exists for other singleton contracts.  Someone is running a backrunner bot that looks for leftover funds in the `RailgunSmartWallet` contract and steals them:
    - Unshield: https://etherscan.io/tx/0x52ce5f786116a0a8fa5463a3b291d9ea7c318422e8d0ee5747f5203ccb54952d
    - Attacker: https://etherscan.io/tx/0x36d349ed36884f64436515eb6e3fc03cae6fc791d37b78e15aabb1fb3386f134


## Changelog
2026_05_06 - Created. This attack was already solved by switching to 7702-senders.