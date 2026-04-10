# 4337 Privacy Paymasters

Privacy protocols require some method of seeding new private addresses. TC, Railgun, Privacy Pools, et al. use their own custom relayer approaches, where the gas fee for withdrawal is deducted from the shielded balance. These different approachs can be unreliable (IE waku network) or unavailable (IE tornadocash on certain chains) and generally require interfacing with a centralized service. Using a custom 4337 paymaster for each privacy protocol, it should be possible to make much more robust system.

The paymasters described here are structurally similar to [ERC20 paymasters](https://docs.erc4337.io/paymasters/types.html#erc-20-paymaster-token-paymaster). They rely on being able to guarantee availability of payment during the `validatePaymasterUserOp` call.

## Limitations / Questions
1. Unshielding:

The paymaster needs to collect a fee from each withdrawal. How this works depends on the protocol, but in general: the user either pays the fee as a separate output or sends the full amount to the paymaster for forwarding.

 - Separate fee output: The user withdraws directly to their destination and pays the paymaster separately in the same transaction. Involves unshielding two UTXO notes. In railgun this can be a single operation, while with ppv1 or tornadocash two seperate calls would be made (however, only the fee call needs to be validated ahead of time).
 - Paymaster forwarding: The full withdrawal goes to the paymaster, which deducts the fee and forwards the rest. Required when the fee and primary withdrawal come from the same note.

Adding seperate fee output for TC may not be required, since TC has such a small set of token pools.

2. Railgun PPOI: 

Because PPOI Merkle tries are entirely off-chain, paymasters won't be able to perform any verification or filtering. I consider this acceptable. While most railgun broadcasters do enforce PPOI requirements, they don't need to (configurable) and the railgun smart contracts do nothing to prevent spending blocked funds. Railgun accepts fees from unverified fund operations, so why shouldn't we.

3. Railgun transactions may charge unlimited gas:

By default, railgun could charge unlimited amounts of gas in the validation step by bundling multiple railgun transactions (`Transaction`) in the call to `function transact(Transaction[] calldata _transactions) external`. To avoid this, we should assert that for railgun the first railgun transaction MUST only include two operations (the fee unshield and a change note). 

 - When validating, we only need to validate the first transaction which is size-constrained. 
 - When executing, we should call `transact` twice - once with the fee transaction and once with the remainder. This way if any are invalid we can still claim our fee.

This breaking of atomicity for `transact` should be noted, but I can't think of any issues.

4. Double-validation

Because both the paymaster and privacy protocol need to validate the provided proof, validation happens twice. This increases overal gas costs for the user by approximately the `Validation Gas` from the above risks table. In general this is ~300k gas (~30k GWEI, $0.06 at current rates). This is unfortunate but acceptable.

In theory, it's possible to skip double-validation. If we assume that (1) the only way to invalidate a previously valid note is to spend that note and (2) that bundlers always simulate the operation, then we can rely on the bundler's off-chain verification. On-chain we can check if the notes have been nullified and, if not, we know they must still be valid. This substantially decreases the validation cost (to <100k gas). However, this also risks the paymaster since the tx can now fail in the execution phase where the paymaster will be charged.
