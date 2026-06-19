# 4337 Privacy Paymasters

Privacy protocols require some method of seeding new private addresses. TC, Railgun, Privacy Pools, et al. use their own custom relayer approaches, where the gas fee for withdrawal is deducted from the shielded balance. These different approachs can be unreliable (IE waku network) or unavailable (IE tornadocash on certain chains) and generally require interfacing with a centralized service. Using a custom 4337 paymaster for each privacy protocol, it should be possible to make much more robust system.

The paymasters described here are structurally similar to [ERC20 paymasters](https://docs.erc4337.io/paymasters/types.html#erc-20-paymaster-token-paymaster). They rely on being able to guarantee availability of payment during the `validatePaymasterUserOp` call.
