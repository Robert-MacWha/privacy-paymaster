interface IPrivacyProtocolsEntrypoint {
    function relay(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        ProofLib.WithdrawProof calldata _proof,
        uint256 _scope
    ) external;
}
