## Railgun Fixtures

To regenerate the railgun fixtures:
1. Select the fork block.
2. Create a railgun 0xzk wallet as the paymaster's "fee-receiver" address and records its 0xkz-address and master public key.
3. Create a second railgun 0xzk wallet as the fee-paying address.
4. Generate the shield fixtures with a shield transaction into the fee-paying address, recording the preimage and ciphertext.
5. Generate the transact fixtures with a transaction from the fee-paying address to any other address, making sure to include a fee-paying commitment in the transaction to the paymaster's fee-receiver address that pays sufficient fees for the transaction and recording the calldata.
6. Manually generate the paymasterAndData by encoding it as defined in `_decodePaymasterAndData` in the `RailgunAccount` contract.  NOTE: the paymasterAndData has a 52-byte prefix that stores metadata, which can be all zeros for the fixtures, followed by the encoded data.
