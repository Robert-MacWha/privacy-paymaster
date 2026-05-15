use alloy::{
    primitives::{Address, Bytes},
    rpc::types::SignedAuthorization,
    signers::Signature,
};
use serde::{Deserialize, Serialize};

use crate::UserOperation;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[cfg_attr(js, derive(tsify::Tsify))]
#[cfg_attr(js, tsify(into_wasm_abi, from_wasm_abi))]
#[serde(rename_all = "camelCase")]
/// A signed 4337 UserOperation with an optional signed 7702 Authorization,
/// ready to be sent to the bundler.
pub struct SignedUserOperation {
    #[serde(flatten)]
    pub user_op: UserOperation,
    pub signature: Bytes,
    #[serde(rename = "eip7702Auth", skip_serializing_if = "Option::is_none")]
    pub authorization: Option<SignedAuthorization>,

    pub entry_point: Address,
}

impl SignedUserOperation {
    pub fn signature(&self) -> Signature {
        //? Always safe to unwrap since we know the signature was generated
        //? in the constructor `sign` method
        Signature::try_from(self.signature.as_ref()).expect("Invalid signature")
    }
}
