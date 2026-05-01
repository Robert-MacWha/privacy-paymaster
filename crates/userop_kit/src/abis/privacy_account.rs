use alloy_sol_macro::sol;

sol! {
    interface IPrivacyAccount {
        struct Call {
            address target;
            bytes data;
        }

        function execute(
            bytes calldata feeCalldata,
            Call[] calldata tail
        ) external;
    }
}
