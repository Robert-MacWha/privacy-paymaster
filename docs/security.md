
## Priorities

1. User fund safety: The user should always be able to retain full custody of all their funds. Unshielded funds should be transferred from the privacy protocol to the user's destination address without passing through the paymaster's control. This mitigates any risk of bugs in the paymaster leading to loss of user funds.
2. Paymaster fund safety: The paymaster should never be at risk of losing funds or being griefed by attackers. The paymaster must validate all proofs and be certain that it will receive a fee that covers the cost of validation before accepting a user operation.

By following these two principles, we eliminate any user attack surface and minimize paymaster attack surface. Remaining risks are outlined in the next sections.

## Assumptions

| Assumption                                           | Basis                                                                           | Risk                                                                                                 |
| ---------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Validation is cheaper than spending                  | Validation is a part of spending, so it should cost strictly less gas           | Griefing                                                                                             |
| The only way to invalidate a proof is by spending it | Holds true for TC, Privacy Pools, and Railgun                                   | Bypassing assumption 1                                                                               |
| Validation guarantees spendability                   | Validation is the check performed by pools to allow spendability                | `validatePaymasterUserOp` passes but `executeUserOp` fails                                           |
| Validation fits in MAX_VERIFICATION_GAS              | Holds true for TC, Privacy Pools, and Railgun                                   | Incompatible with said privacy protocol                                                              |
| Staked paymaster can read privacy protocol's storage | [STO-033](eips.ethereum.org/EIPS/eip-7562#storage-rules)                        |                                                                                                      |
| Bundlers are frontrun-protected                      | Economic incentives to do so. Similar risk is present in all erc-20 paymasters. | Third parties can frontrun bundles after simulation and invalidate proofs, leading to bundler losses |

## Risks

### Griefing

Griefing can happen if the off-chain validation simulation passes, but on-chain validation fails. This happens when an attacker has a valid unshield operation in simulation and frontruns the bundler's transaction to invalidate the operation on-chain. The cost to grief the paymaster is significantly higher than the cost incurred by said paymaster.

This risk is the same as that faced by regular unpermissioned ERC20 paymasters. If the attacker frontruns a bundler's transaction and drains their funds, then the transferFrom call will fail and the bundler will eat the gas. The paymaster should never be at risk of losing funds.

If an attacker already has shielded notes, they can attack by unshielding those notes. If an attacker does not have shielded notes, they must first create them by shielding tokens. Both attack vectors are outlined below.

| Protocol       | Validation Gas                                                                                                                     | Attack Gas (existing note)                                                                                                         | Attack Gas (fresh deposit + withdraw)                                                                                                | Ratio (existing) | Ratio (fresh) |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ---------------- | ------------- |
| Tornadocash    | [~240k](https://dashboard.tenderly.co/shield3/rob/tx/0x4af5b29234e5fc9517715ae586bcd258096ab29ca4a738b30dddb53ab9bf361d/gas-usage) | [~400k](https://dashboard.tenderly.co/shield3/rob/tx/0x4af5b29234e5fc9517715ae586bcd258096ab29ca4a738b30dddb53ab9bf361d/gas-usage) | [~1300k](https://dashboard.tenderly.co/shield3/rob/tx/0x8c59fcb05cea33267a85ec80cc5cd8dffe12c3031bdb203db292400a63e5205e/gas-usage)  | 1.67:1           | 5.4:1         |
| Privacy Pools* | [~250k](https://dashboard.tenderly.co/shield3/rob/tx/0xc85c02c634a1a608be8a66b3ae48d0349042ac857eee8324fae0cb14e09c261a/gas-usage) | [~580k](https://dashboard.tenderly.co/shield3/rob/tx/0xc85c02c634a1a608be8a66b3ae48d0349042ac857eee8324fae0cb14e09c261a/gas-usage) | [~1_000k](https://dashboard.tenderly.co/shield3/rob/tx/0x5e4e914c9e1fb7bf438064b05de6693b43c631ba6074359d19a946caf8bd2c89/gas-usage) | 2.3:1            | 4:1           |
| Railgun**      | [~335k](https://dashboard.tenderly.co/shield3/rob/tx/0xab7da259039f0bfd91111b3fb92f362fa59a500c6a73a8340ac853813e92f789/gas-usage) | [~482k](https://dashboard.tenderly.co/shield3/rob/tx/0xab7da259039f0bfd91111b3fb92f362fa59a500c6a73a8340ac853813e92f789/gas-usage) | [~1200k](https://dashboard.tenderly.co/shield3/rob/tx/0x979ed63ac23b275188ebf42e5c2293f90222a7bec0b4bea3e43f3121c1cab258/gas-usage)  | 2.67:1           | 4.2:1         |

\* Because Privacy Pools enforces ASP on-chain, attackers will also be semi-rate-limited. This doesn't actually reduce potential damages, just slows down any attacks.

** Railgun txns are much more variable than privacy pools or TC. I attempted to find worse-case txns, but the actual numbers are likely lower. Testing would be performed to ensure the ratio never approaches 1:1.
