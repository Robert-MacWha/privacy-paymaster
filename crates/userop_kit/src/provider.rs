use std::sync::Arc;

use alloy_primitives::{Address, B256, U256, aliases::U192};
use alloy_provider::Provider;
use alloy_rpc_client::RpcClient;
use alloy_rpc_types::{Log, TransactionInput, TransactionReceipt, TransactionRequest};
use alloy_sol_macro::sol;
use alloy_sol_types::SolCall;
use serde::{Deserialize, Serialize};

use crate::BundlerError;
use crate::{UserOperation, UserOperationHash};

sol! {
    contract EntryPoint {
        function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
    }
}

/// Gas estimates returned by `eth_estimateUserOperationGas`.
///
/// EntryPoint 0.7 & 0.8
#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(target_arch = "wasm32", derive(tsify::Tsify))]
#[cfg_attr(target_arch = "wasm32", tsify(into_wasm_abi, from_wasm_abi))]
#[serde(rename_all = "camelCase")]
pub struct UserOperationGasEstimate {
    pub pre_verification_gas: U256,
    pub verification_gas_limit: U256,
    pub call_gas_limit: U256,
    #[serde(default)]
    pub paymaster_verification_gas_limit: Option<U256>,
    #[serde(default)]
    pub paymaster_post_op_gas_limit: Option<U256>,
}

/// Receipt returned by `eth_getUserOperationReceipt`.
///
/// EntryPoint 0.7 & 0.8
#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(target_arch = "wasm32", derive(tsify::Tsify))]
#[cfg_attr(target_arch = "wasm32", tsify(into_wasm_abi, from_wasm_abi))]
#[serde(rename_all = "camelCase")]
pub struct UserOperationReceipt {
    pub entry_point: Address,
    pub user_op_hash: B256,
    pub sender: Address,
    pub nonce: U256,
    pub actual_gas_used: U256,
    pub actual_gas_cost: U256,
    pub success: bool,
    pub logs: Vec<Log>,
    pub receipt: TransactionReceipt,
}

#[derive(Clone)]
pub struct BundlerProvider {
    eth: Arc<dyn Provider>,
    bundler: RpcClient,
    entry_point: Address,
}

impl BundlerProvider {
    pub fn new(
        eth: Arc<dyn Provider>,
        bundler: RpcClient,
        entry_point: Address,
    ) -> Result<Self, BundlerError> {
        Ok(Self {
            eth,
            bundler,
            entry_point,
        })
    }

    /// Fetch the packed nonce from the EntryPoint.
    pub async fn get_nonce(&self, sender: Address, key: U192) -> Result<U256, BundlerError> {
        let calldata = EntryPoint::getNonceCall { sender, key }.abi_encode();
        let res = self
            .eth
            .call(
                TransactionRequest::default()
                    .to(self.entry_point)
                    .input(TransactionInput::both(calldata.into())),
            )
            .await
            .map_err(BundlerError::Transport)?;

        let nonce =
            EntryPoint::getNonceCall::abi_decode_returns(&res).map_err(BundlerError::Abi)?;
        Ok(nonce)
    }

    pub async fn suggest_max_fee_per_gas(&self) -> Result<u128, BundlerError> {
        self.eth
            .get_gas_price()
            .await
            .map_err(BundlerError::Transport)
    }

    pub async fn suggest_max_priority_fee_per_gas(&self) -> Result<u128, BundlerError> {
        self.eth
            .get_max_priority_fee_per_gas()
            .await
            .map_err(BundlerError::Transport)
    }
}

// Bundler JSON-RPC
impl BundlerProvider {
    pub async fn estimate_gas(
        &self,
        op: &UserOperation,
    ) -> Result<UserOperationGasEstimate, BundlerError> {
        self.bundler
            .request("eth_estimateUserOperationGas", (op, self.entry_point))
            .await
            .map_err(BundlerError::Transport)
    }

    pub async fn send_user_operation(
        &self,
        op: &UserOperation,
    ) -> Result<UserOperationHash, BundlerError> {
        let hash: B256 = self
            .bundler
            .request("eth_sendUserOperation", (op, self.entry_point))
            .await
            .map_err(BundlerError::Transport)?;

        Ok(UserOperationHash(hash))
    }

    pub async fn wait_for_receipt(
        &self,
        hash: UserOperationHash,
    ) -> Result<UserOperationReceipt, BundlerError> {
        loop {
            let receipt: Option<UserOperationReceipt> = self
                .bundler
                .request("eth_getUserOperationReceipt", (hash.0,))
                .await
                .map_err(BundlerError::Transport)?;

            if let Some(r) = receipt {
                return Ok(r);
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
