## Tornadocash Fixtures

To regenerate the tornadocash fixtures:
1. Selecting the fork block
2. Select the tornadocash pool to use for testing (e.g. 0.1 ETH)
3. Deploying the PrivacyPaymaster to a forked chain on that block to obtain the resulting address
4. Generate the deposit commitment for the selected pool
5. Generate the unshield fixtures using the PrivacyPaymaster's address as the relayer, and with the fee sufficient to cover the gas cost of the unshield transaction
