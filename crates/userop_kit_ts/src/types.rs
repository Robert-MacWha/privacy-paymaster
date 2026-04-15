use std::str::FromStr;

use alloy_primitives::{Address, U128, Uint};
use serde::{Deserialize, Serialize};
use tsify::Tsify;
use wasm_bindgen::JsError;
use wasm_bindgen_futures::js_sys::BigInt;

#[derive(Tsify, Serialize, Deserialize)]
#[tsify(into_wasm_abi, from_wasm_abi)]
pub struct JsAddress(#[tsify(type = "`0x${string}`")] pub String);

impl TryFrom<JsAddress> for Address {
    type Error = JsError;
    fn try_from(value: JsAddress) -> Result<Self, Self::Error> {
        let addr: Address = value.0.parse()?;
        Ok(addr)
    }
}

impl From<Address> for JsAddress {
    fn from(value: Address) -> Self {
        Self(value.to_string())
    }
}

pub fn bigint_to_uint<const BITS: usize, const LIMBS: usize>(
    v: BigInt,
) -> Result<Uint<BITS, LIMBS>, JsError> {
    if v < BigInt::from(0) {
        return Err(JsError::new("Negative value cannot be converted to Uint"));
    }

    let hex = v
        .to_string(16)
        .map_err(|e| JsError::new(&format!("Invalid BigInt: {e:?}")))?
        .as_string()
        .unwrap();
    Ok(Uint::from_str_radix(&hex, 16)?)
}

pub fn bigint_to_u128(v: BigInt) -> Result<u128, JsError> {
    let u: U128 = bigint_to_uint(v)?;
    Ok(u.to())
}

pub fn uint_to_bigint<const BITS: usize, const LIMBS: usize>(v: Uint<BITS, LIMBS>) -> BigInt {
    BigInt::from_str(&format!("0x{:x}", v)).expect("valid hex uint")
}
