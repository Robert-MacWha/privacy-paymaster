use alloy_primitives::{Address, Bytes, aliases::U192};
use wasm_bindgen::{JsError, prelude::wasm_bindgen};
use wasm_bindgen_futures::js_sys::BigInt;

use crate::provider::BundlerProvider;
use crate::types::{JsAddress, bigint_to_u128, bigint_to_uint};

#[wasm_bindgen]
pub struct UserOperationBuilder {
    inner: userop_kit::UserOperationBuilder,
}

#[wasm_bindgen]
impl UserOperationBuilder {
    #[wasm_bindgen(constructor)]
    pub fn new(sender: JsAddress) -> Result<UserOperationBuilder, JsError> {
        let sender: Address = sender
            .try_into()
            .map_err(|e| JsError::new(&format!("Invalid sender: {e:?}")))?;
        Ok(UserOperationBuilder {
            inner: userop_kit::UserOperationBuilder::new(sender),
        })
    }

    #[wasm_bindgen(js_name = "withCalldata")]
    pub fn with_calldata(self, calldata: Vec<u8>) -> UserOperationBuilder {
        UserOperationBuilder {
            inner: self.inner.with_calldata(Bytes::from(calldata)),
        }
    }

    #[wasm_bindgen(js_name = "withPaymaster")]
    pub fn with_paymaster(self, paymaster: JsAddress) -> Result<UserOperationBuilder, JsError> {
        let paymaster: Address = paymaster
            .try_into()
            .map_err(|e| JsError::new(&format!("Invalid paymaster: {e:?}")))?;
        Ok(UserOperationBuilder {
            inner: self.inner.with_paymaster(paymaster),
        })
    }

    #[wasm_bindgen(js_name = "withPaymasterData")]
    pub fn with_paymaster_data(self, data: Vec<u8>) -> UserOperationBuilder {
        UserOperationBuilder {
            inner: self.inner.with_paymaster_data(Bytes::from(data)),
        }
    }

    #[wasm_bindgen(js_name = "withSignature")]
    pub fn with_signature(self, sig: Vec<u8>) -> UserOperationBuilder {
        UserOperationBuilder {
            inner: self.inner.with_signature(Bytes::from(sig)),
        }
    }

    #[wasm_bindgen(js_name = "withNonceKey")]
    pub fn with_nonce_key(self, key: BigInt) -> Result<UserOperationBuilder, JsError> {
        let key: U192 = bigint_to_uint(key)?;
        Ok(UserOperationBuilder {
            inner: self.inner.with_nonce_key(key),
        })
    }

    #[wasm_bindgen(js_name = "withGas")]
    pub fn with_gas(
        self,
        call_gas_limit: BigInt,
        verification_gas_limit: BigInt,
        pre_verification_gas: BigInt,
        max_fee_per_gas: BigInt,
        max_priority_fee_per_gas: BigInt,
        paymaster_verification_gas_limit: BigInt,
        paymaster_post_op_gas_limit: BigInt,
    ) -> Result<UserOperationBuilder, JsError> {
        Ok(UserOperationBuilder {
            inner: self.inner.with_gas(
                bigint_to_u128(call_gas_limit)?,
                bigint_to_u128(verification_gas_limit)?,
                bigint_to_u128(pre_verification_gas)?,
                bigint_to_u128(max_fee_per_gas)?,
                bigint_to_u128(max_priority_fee_per_gas)?,
                bigint_to_u128(paymaster_verification_gas_limit)?,
                bigint_to_u128(paymaster_post_op_gas_limit)?,
            ),
        })
    }

    #[wasm_bindgen(js_name = "withFactory")]
    pub fn with_factory(
        self,
        factory: JsAddress,
        data: Vec<u8>,
    ) -> Result<UserOperationBuilder, JsError> {
        let factory: Address = factory
            .try_into()
            .map_err(|e| JsError::new(&format!("Invalid factory: {e:?}")))?;
        Ok(UserOperationBuilder {
            inner: self.inner.with_factory(factory, Bytes::from(data)),
        })
    }

    pub async fn build(
        self,
        provider: &BundlerProvider,
    ) -> Result<userop_kit::UserOperation, JsError> {
        self.inner
            .build(&provider.inner)
            .await
            .map_err(|e| JsError::new(&format!("{e}")))
    }
}
