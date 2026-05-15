use std::sync::Arc;

use reqwest::Url;
use wasm_bindgen::{JsError, prelude::wasm_bindgen};

use crate::{
    SignedUserOperation, UserOperation, UserOperationGasEstimate, UserOperationHash,
    UserOperationReceipt,
    bundler::{BundlerProvider, pimlico::PimlicoBundler},
};

#[wasm_bindgen(js_name = "Bundler")]
pub struct JsBundler {
    inner: Arc<dyn BundlerProvider>,
}

impl JsBundler {
    pub fn new(inner: Arc<dyn BundlerProvider>) -> Self {
        Self { inner }
    }

    pub fn inner(&self) -> Arc<dyn BundlerProvider> {
        self.inner.clone()
    }
}

#[wasm_bindgen]
impl JsBundler {
    /// Creates a new Pimlico bundler provider.
    #[wasm_bindgen(js_name = "pimlico")]
    pub fn new_pimlico(bundler_url: String) -> Result<Self, JsError> {
        let bundler_url = Url::parse(&bundler_url).map_err(|e| JsError::new(&e.to_string()))?;

        Ok(Self {
            inner: Arc::new(PimlicoBundler::new(bundler_url)),
        })
    }
}

#[wasm_bindgen]
impl JsBundler {
    #[wasm_bindgen(js_name = "suggestMaxFeePerGas")]
    pub async fn suggest_max_fee_per_gas(&self) -> Result<u128, JsError> {
        self.inner
            .suggest_max_fee_per_gas()
            .await
            .map_err(|e| JsError::new(&e.to_string()))
    }

    #[wasm_bindgen(js_name = "suggestMaxPriorityFeePerGas")]
    pub async fn suggest_max_priority_fee_per_gas(&self) -> Result<u128, JsError> {
        self.inner
            .suggest_max_priority_fee_per_gas()
            .await
            .map_err(|e| JsError::new(&e.to_string()))
    }

    #[wasm_bindgen(js_name = "estimateGas")]
    pub async fn estimate_gas(
        &self,
        op: UserOperation,
    ) -> Result<UserOperationGasEstimate, JsError> {
        self.inner
            .estimate_gas(&op)
            .await
            .map_err(|e| JsError::new(&e.to_string()))
    }

    #[wasm_bindgen(js_name = "sendUserOperation")]
    pub async fn send_user_operation(
        &self,
        op: SignedUserOperation,
    ) -> Result<UserOperationHash, JsError> {
        self.inner
            .send_user_operation(&op)
            .await
            .map_err(|e| JsError::new(&e.to_string()))
    }

    #[wasm_bindgen(js_name = "waitForReceipt")]
    pub async fn wait_for_receipt(
        &self,
        hash: UserOperationHash,
    ) -> Result<UserOperationReceipt, JsError> {
        self.inner
            .wait_for_receipt(hash)
            .await
            .map_err(|e| JsError::new(&e.to_string()))
    }
}
