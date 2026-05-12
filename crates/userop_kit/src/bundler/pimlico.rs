use alloy::primitives::{Address, B256};
use alloy::sol_types::{Eip712Domain, eip712_domain};
use reqwest::Url;
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::bundler::bundler::BundlerError;
use crate::bundler::bundler::BundlerProvider;
use crate::bundler::rpc_client::{RpcClient, RpcClientError};
use crate::signed_user_operation::SignedUserOperation;
use crate::{UserOperation, UserOperationGasEstimate, UserOperationHash, UserOperationReceipt};

pub struct PimlicoBundler {
    client: RpcClient,
    chain_id: u64,
    entry_point: Address,
    domain: Eip712Domain,
}

/// Errors from the bundler SDK.
#[derive(Debug, thiserror::Error)]
pub enum PimlicoError {
    #[error("Transport error: {0}")]
    Transport(#[from] RpcClientError),

    #[error("Abi error: {0}")]
    Abi(#[from] alloy::sol_types::Error),
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
    #[serde(with = "alloy::serde::quantity")]
    pub max_fee_per_gas: u128,
    #[serde(with = "alloy::serde::quantity")]
    pub max_priority_fee_per_gas: u128,
}

impl PimlicoBundler {
    pub fn new(bundler_url: Url, chain_id: u64, entry_point: Address) -> Self {
        let domain = eip712_domain! {
            name: "ERC4337",
            version: "1",
            chain_id: chain_id,
            verifying_contract: entry_point,
        };

        Self {
            client: RpcClient::new(bundler_url),
            chain_id,
            entry_point,
            domain,
        }
    }

    pub fn set_eip712_domain(&mut self, domain: Eip712Domain) {
        self.domain = domain;
    }
}

impl BundlerProvider for PimlicoBundler {
    fn chain_id(&self) -> u64 {
        self.chain_id
    }

    fn entry_point(&self) -> Address {
        self.entry_point
    }

    fn eip712_domain(&self) -> Eip712Domain {
        self.domain.clone()
    }

    async fn suggest_max_fee_per_gas(&self) -> Result<u128, BundlerError> {
        info!("Requesting max fee estimate from Pimlico...");
        let estimate: PimlicoUserOperationGasEstimate = self
            .client
            .request("pimlico_getUserOperationGasPrice", serde_json::json!([]))
            .await
            .map_err(|e| BundlerError::Other(Box::new(e)))?;

        Ok(estimate.standard.max_fee_per_gas)
    }

    async fn suggest_max_priority_fee_per_gas(&self) -> Result<u128, BundlerError> {
        info!("Requesting max priority fee estimate from Pimlico...");
        let estimate: PimlicoUserOperationGasEstimate = self
            .client
            .request("pimlico_getUserOperationGasPrice", serde_json::json!([]))
            .await
            .map_err(|e| BundlerError::Other(Box::new(e)))?;

        Ok(estimate.standard.max_priority_fee_per_gas)
    }

    async fn estimate_gas(
        &self,
        op: &UserOperation,
    ) -> Result<UserOperationGasEstimate, BundlerError> {
        info!("Requesting gas estimate from Pimlico...");

        Ok(self
            .client
            .request("eth_estimateUserOperationGas", (op, self.entry_point))
            .await
            .map_err(|e| BundlerError::Other(Box::new(e)))?)
    }

    async fn send_user_operation(
        &self,
        op: &SignedUserOperation,
    ) -> Result<UserOperationHash, BundlerError> {
        info!("Sending user operation to Pimlico...");
        let hash: B256 = self
            .client
            .request("eth_sendUserOperation", (op, self.entry_point))
            .await
            .map_err(|e| BundlerError::Other(Box::new(e)))?;

        Ok(UserOperationHash(hash))
    }

    async fn wait_for_receipt(
        &self,
        hash: UserOperationHash,
    ) -> Result<UserOperationReceipt, BundlerError> {
        info!("Waiting for user operation receipt from Pimlico...");

        for _ in 0..5 {
            let receipt: Option<UserOperationReceipt> = self
                .client
                .request("eth_getUserOperationReceipt", (hash.0,))
                .await
                .map_err(|e| BundlerError::Other(Box::new(e)))?;

            if let Some(r) = receipt {
                return Ok(r);
            }

            info!("User operation not yet included, retrying...");
            #[cfg(not(target_arch = "wasm32"))]
            {
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            }

            #[cfg(target_arch = "wasm32")]
            gloo_timers::future::TimeoutFuture::new(2_000).await;
        }

        Err(BundlerError::Timeout)
    }
}
