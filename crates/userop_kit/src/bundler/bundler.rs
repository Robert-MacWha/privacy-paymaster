use alloy_primitives::{Address, U256, aliases::U192};

use crate::{UserOperation, UserOperationGasEstimate, UserOperationHash};

pub trait BundlerProvider {
    type Error: std::error::Error;
    fn suggest_max_fee_per_gas(
        &self,
    ) -> impl std::future::Future<Output = Result<u128, Self::Error>>;
    fn suggest_max_priority_fee_per_gas(
        &self,
    ) -> impl std::future::Future<Output = Result<u128, Self::Error>>;
    fn estimate_gas(
        &self,
        op: &UserOperation,
    ) -> impl std::future::Future<Output = Result<UserOperationGasEstimate, Self::Error>>;
    fn send_user_operation(
        &self,
        op: &UserOperation,
    ) -> impl std::future::Future<Output = Result<UserOperationHash, Self::Error>>;
    fn wait_for_receipt(
        &self,
        hash: UserOperationHash,
    ) -> impl std::future::Future<Output = Result<(), Self::Error>>;
}
