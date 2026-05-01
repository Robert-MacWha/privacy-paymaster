use alloy_primitives::{Address, B256};
use reqwest::Url;
use serde::{Deserialize, Serialize};

use crate::bundler::BundlerProvider;
use crate::bundler::rpc_client::{RpcClient, RpcClientError};
use crate::{UserOperation, UserOperationGasEstimate, UserOperationHash, UserOperationReceipt};

pub struct PimlicoBundler {
    bundler: RpcClient,
    entry_point: Address,
}

/// Errors from the bundler SDK.
#[derive(Debug, thiserror::Error)]
pub enum PimlicoError {
    #[error("Transport error: {0}")]
    Transport(#[from] RpcClientError),

    #[error("Abi error: {0}")]
    Abi(#[from] alloy_sol_types::Error),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PimlicoUserOperationGasEstimate {
    pub slow: PimlicoSpeedGasEstimate,
    pub standard: PimlicoSpeedGasEstimate,
    pub fast: PimlicoSpeedGasEstimate,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PimlicoSpeedGasEstimate {
    pub max_fee_per_gas: u128,
    pub max_priority_fee_per_gas: u128,
}

impl PimlicoBundler {
    pub fn new(bundler_url: Url, entry_point: Address) -> Result<Self, PimlicoError> {
        Ok(Self {
            bundler: RpcClient::new(bundler_url),
            entry_point,
        })
    }
}

impl BundlerProvider for PimlicoBundler {
    type Error = PimlicoError;

    async fn suggest_max_fee_per_gas(&self) -> Result<u128, Self::Error> {
        let estimate: PimlicoUserOperationGasEstimate = self
            .bundler
            .request("pimlico_getUserOperationGasPrice", ())
            .await?;

        Ok(estimate.standard.max_fee_per_gas)
    }

    async fn suggest_max_priority_fee_per_gas(&self) -> Result<u128, Self::Error> {
        let estimate: PimlicoUserOperationGasEstimate = self
            .bundler
            .request("pimlico_getUserOperationGasPrice", ())
            .await?;

        Ok(estimate.standard.max_priority_fee_per_gas)
    }

    async fn estimate_gas(
        &self,
        op: &UserOperation,
    ) -> Result<UserOperationGasEstimate, Self::Error> {
        Ok(self
            .bundler
            .request("eth_estimateUserOperationGas", (op, self.entry_point))
            .await?)
    }

    async fn send_user_operation(
        &self,
        op: &UserOperation,
    ) -> Result<UserOperationHash, Self::Error> {
        let hash: B256 = self
            .bundler
            .request("eth_sendUserOperation", (op, self.entry_point))
            .await?;

        Ok(UserOperationHash(hash))
    }

    async fn wait_for_receipt(&self, hash: UserOperationHash) -> Result<(), Self::Error> {
        loop {
            let receipt: Option<UserOperationReceipt> = self
                .bundler
                .request("eth_getUserOperationReceipt", (hash.0,))
                .await?;

            if let Some(_r) = receipt {
                return Ok(());
            }

            #[cfg(not(target_arch = "wasm32"))]
            {
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            }

            #[cfg(target_arch = "wasm32")]
            gloo_timers::future::TimeoutFuture::new(2_000).await;
        }
    }
}
