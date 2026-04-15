use alloy_primitives::{Address, U128, aliases::U192};
use alloy_provider::{DynProvider, Provider, ProviderBuilder};
use alloy_rpc_client::RpcClient;
use wasm_bindgen::{JsError, prelude::wasm_bindgen};
use wasm_bindgen_futures::js_sys::BigInt;

use crate::types::{JsAddress, bigint_to_uint, uint_to_bigint};

#[wasm_bindgen]
pub struct BundlerProvider {
    pub(crate) inner: userop_kit::BundlerProvider<DynProvider>,
}

#[wasm_bindgen]
impl BundlerProvider {
    pub async fn new(
        rpc_url: String,
        bundler_url: String,
        entry_point: JsAddress,
    ) -> Result<BundlerProvider, JsError> {
        let entry_point: Address = entry_point
            .try_into()
            .map_err(|e| JsError::new(&format!("Invalid entry point: {e:?}")))?;
        let bundler_url = bundler_url
            .parse()
            .map_err(|e| JsError::new(&format!("Invalid bundler URL: {e}")))?;

        let eth_provider = ProviderBuilder::new().connect(&rpc_url).await?.erased();
        let bundler_client = RpcClient::new_http(bundler_url);

        let bundler = userop_kit::BundlerProvider::new(eth_provider, bundler_client, entry_point)?;
        Ok(BundlerProvider { inner: bundler })
    }

    #[wasm_bindgen(js_name = "getNonce")]
    pub async fn get_nonce(&self, sender: JsAddress, key: BigInt) -> Result<BigInt, JsError> {
        let sender: Address = sender
            .try_into()
            .map_err(|e| JsError::new(&format!("Invalid sender address: {e:?}")))?;
        let key: U192 = bigint_to_uint(key)?;

        let nonce = self.inner.get_nonce(sender, key).await?;
        Ok(uint_to_bigint(nonce))
    }

    #[wasm_bindgen(js_name = "suggestMaxFeePerGas")]
    pub async fn suggest_max_fee_per_gas(&self) -> Result<BigInt, JsError> {
        let fee: u128 = self.inner.suggest_max_fee_per_gas().await?;
        Ok(uint_to_bigint(U128::from(fee)))
    }

    #[wasm_bindgen(js_name = "suggestMaxPriorityFeePerGas")]
    pub async fn suggest_max_priority_fee_per_gas(&self) -> Result<BigInt, JsError> {
        let fee: u128 = self.inner.suggest_max_priority_fee_per_gas().await?;
        Ok(uint_to_bigint(U128::from(fee)))
    }

    #[wasm_bindgen(js_name = "estimateGas")]
    pub async fn estimate_gas(
        &self,
        op: userop_kit::UserOperation,
    ) -> Result<userop_kit::UserOperationGasEstimate, JsError> {
        let estimate = self.inner.estimate_gas(&op).await?;
        Ok(estimate)
    }

    #[wasm_bindgen(js_name = "sendUserOperation")]
    pub async fn send_user_operation(
        &self,
        op: userop_kit::UserOperation,
    ) -> Result<userop_kit::UserOperationHash, JsError> {
        let hash = self.inner.send_user_operation(&op).await?;
        Ok(hash)
    }

    #[wasm_bindgen(js_name = "waitForReceipt")]
    pub async fn wait_for_receipt(
        &self,
        hash: userop_kit::UserOperationHash,
    ) -> Result<userop_kit::UserOperationReceipt, JsError> {
        let receipt = self.inner.wait_for_receipt(hash).await?;
        Ok(receipt)
    }
}
