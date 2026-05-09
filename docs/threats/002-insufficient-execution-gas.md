# Insufficient Execution Gas Griefing

## Status
Active

## Threat
Paymasters receive their fee in two phases.  Firstly, in `validatePaymasterUserOp` the paymaster validates that the user operation includes a valid fee payment call (IE for railgun, that the transaction includes a shielded transfer to the paymaster's 0zaddress). Secondly, in `executeUserOp` the paymaster executes the fee-paying call. Given a valid fee payment call, `executeUserOp` can still revert if the user operation doesn't include enough gas for the `execution` phase. The paymaster would pay the cost of the failed transaction, but would not receive any fee.

## Example Attack Scenario
1. Attacker creates a userOperation with a valid fee payment call, but only enough gas for the validation phase.
2. The userOperation is sent to the paymaster.
3. The paymaster validates the userOperation in `validatePaymasterUserOp`, sees that the fee payment call is valid, and accepts the userOperation.
4. The `sender` executes the userOperation, but runs out of gas during the fee payment call and reverts.

The paymaster has now incurred the cost of executing the userOp but has not received any fee. This attack can be repeated indefinitely at no cost to the attacker.

## Cost Analysis
Attacker cost per attempt: 0 (creating and sending a userOperation with insufficient gas is free)
Defender cost per attempt: 1m-2m gas (the attacker can craft a maximally expensive userOperation that still fails. Exact cost is per-protocol, but can be millions of gas)

## Defences
1. Mark validated nullifiers as "spent" in `validatePaymasterUserOp` and reject any userOperations that attempt to spend these again.
   1. Raises the cost of attack to the cost of creating a new nullifiable note.
   2. This doesn't prevent griefing, but it does incur a cost on the attacker and prevent infinite free attacks.
2. Introduce per-protocol minimum gas limits for userOperations. IE for tornadocash, if we know a unshield operation costs at most 500k gas we can set a minimum gas limit of 500k for any userOperation to tc. This places a surplus fee on benign users while preventing attackers from exploiting this vulnerability. The surplus fee should be tuned per-protocol to minimize user impact.
3. Introduce per-protocol complexity limits.  Primarily for railgun, ensures that the number of commitments and nullifiers in a transaction is limited. This enables more accurate gas estimation but might harm users.

## Residual risk
- Balancing the minimum gas limit is difficult.  Too high is burdensome for users, and too low is insufficient to prevent griefing. IMO the best solution is to set it high enough to prevent most griefing in most scenarios and to accept that some edge cases may still be vulnerable. 
  - Tornadocash and PPV1 can be very tightly tuned since gas is highly predictable (TC nearly always <= 350k, PPV1 similarly reliable). 
  - Railgun is highly variable, so needs a much higher minimum. Railgun operations involving a single transaction normally cost 1,120k gas when unshielding or 1,010k gas when transfering:

| Method                          | Gas            | Variability                                                                    | Rough equation                                                                                                  |
| ------------------------------- | -------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| validateTransaction             | ~440k          | depends on whether there is an unshield and on # of nullifiers and commitments | 48k + 100k + 182k + 7000 * (2 + n + c)                                                                          |
| accumulateAndNullifyTransaction | 20k - 200k     | depends on # of nullifiers and commitments                                     | n * 33k                                                                                                         |
| ERC20 Transfer                  | ~70k           | depends on the ERC20 token                                                     |                                                                                                                 |
| insertLeaves                    | 0 or ~700k     | depends on # of hashes                                                         | c == 0 ? 0 : ~44k / hash, but # of hashes is >= 16 and psuedo-random depending on the state of the merkle trie. |
| Total                           | ~1060k - 1410k | High                                                                           |

Using worst-case estimates for railgun, and computing based on the # of commitments, nullifiers, and unshield status, we can set the gas at roughly:
`(330 + 7000 * (2 + n + c)) + (n * 33k) + (unshield ? 70k : 0) + (c == 0 ? 0 : 700k)`

| n   | c   | Unshield | Gas (worst case) | True cost (from arbitrary on-chain sample) |
| --- | --- | -------- | ---------------- | ------------------------------------------ |
| 1   | 2   | yes      | 1,168k           | ~1,085k                                    |
| 1   | 3   | no       | 1,105k           | ~1,022k                                    |
| 1   | 3   | yes      | 1,175k           | ~1,085k                                    |

Average overcharge: ~100k gas.

This equation should be tuned over time as we gather more data.

## Changelog
- 2026_05_06: Initial draft outlining attack, cost to attacker, and initial defences.