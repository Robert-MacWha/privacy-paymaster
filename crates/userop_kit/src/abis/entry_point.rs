use alloy_sol_macro::sol;

sol! {
    contract EntryPoint {
        function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
    }
}
