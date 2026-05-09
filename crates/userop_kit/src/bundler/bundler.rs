use alloy::{primitives::Address, sol_types::Eip712Domain};
use thiserror::Error;

use crate::{UserOperation, UserOperationGasEstimate, UserOperationHash, UserOperationReceipt};

#[derive(Debug, Error)]
pub enum BundlerError {
    #[error("Timeout")]
    Timeout,
    #[error("Other: {0}")]
    Other(#[from] Box<dyn std::error::Error + Send + Sync>),
}

pub trait BundlerProvider {
    fn chain_id(&self) -> u64;
    fn entry_point(&self) -> Address;
    fn eip712_domain(&self) -> Eip712Domain;

    fn suggest_max_fee_per_gas(
        &self,
    ) -> impl std::future::Future<Output = Result<u128, BundlerError>>;
    fn suggest_max_priority_fee_per_gas(
        &self,
    ) -> impl std::future::Future<Output = Result<u128, BundlerError>>;
    fn estimate_gas(
        &self,
        op: &UserOperation,
    ) -> impl std::future::Future<Output = Result<UserOperationGasEstimate, BundlerError>>;
    fn send_user_operation(
        &self,
        op: &UserOperation,
    ) -> impl std::future::Future<Output = Result<UserOperationHash, BundlerError>>;
    fn wait_for_receipt(
        &self,
        hash: UserOperationHash,
    ) -> impl std::future::Future<Output = Result<UserOperationReceipt, BundlerError>>;
}
