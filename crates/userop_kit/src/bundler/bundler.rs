use thiserror::Error;

use crate::{
    UserOperation, UserOperationGasEstimate, UserOperationHash, UserOperationReceipt,
    signed_user_operation::SignedUserOperation,
};

#[derive(Debug, Error)]
pub enum BundlerError {
    #[error("Timeout")]
    Timeout,
    #[error("Other: {0}")]
    Other(#[from] Box<dyn std::error::Error + Send + Sync>),
}

#[cfg_attr(native, async_trait::async_trait)]
#[cfg_attr(wasm, async_trait::async_trait(?Send))]
pub trait BundlerProvider {
    async fn suggest_max_fee_per_gas(&self) -> Result<u128, BundlerError>;
    async fn suggest_max_priority_fee_per_gas(&self) -> Result<u128, BundlerError>;
    async fn estimate_gas(
        &self,
        op: &UserOperation,
    ) -> Result<UserOperationGasEstimate, BundlerError>;
    async fn send_user_operation(
        &self,
        op: &SignedUserOperation,
    ) -> Result<UserOperationHash, BundlerError>;
    async fn wait_for_receipt(
        &self,
        hash: UserOperationHash,
    ) -> Result<UserOperationReceipt, BundlerError>;
}
