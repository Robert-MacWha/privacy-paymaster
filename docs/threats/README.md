# Threats

This directory outlines various security classes & risks the privacy-protocol paymaster design faces.

## Classes

Classes of attacks are those that share a common root cause, but may have different attack vectors or implementation details.

### Greefing

Attacks that cause the paymaster to lose funds or be unable to recover the gas spent on executing a user operation. This can happen if the paymaster accepts a userOp that, when executed, does not pay the paymaster's fee.

- [002 Insufficient Execution Gas](./002-insufficient-execution-gas.md)

### User fund loss

Attacks that cause users to lose funds. These can happen if a user's funds are at any time owned or permissioned to an account not controlled by the user.

- [001 Leftover Funds](./001-4337-leftover-funds.md)

### Privacy degradation

Attacks that cause the privacy guarantees of the underlying protocol to be weakened. This can happen if any actions that would normally be private are made public, or if the anonymity set is reduced in any way.
