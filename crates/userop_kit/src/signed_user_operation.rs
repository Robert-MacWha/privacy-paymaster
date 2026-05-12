use alloy::{primitives::Bytes, rpc::types::SignedAuthorization, signers::Signature};
use serde::{Deserialize, Serialize};

use crate::UserOperation;

#[derive(Serialize, Deserialize)]
/// A signed 4337 UserOperation with an optional signed 7702 Authorization,
/// ready to be sent to the bundler.
pub struct SignedUserOperation {
    #[serde(flatten)]
    pub user_op: UserOperation,
    pub signature: Bytes,

    #[serde(rename = "eip7702Auth", skip_serializing_if = "Option::is_none")]
    pub authorization: Option<SignedAuthorization>,
}

impl SignedUserOperation {
    pub fn signature(&self) -> Signature {
        //? Always safe to unwrap since we know the signature was generated
        //? in the constructor `sign` method
        Signature::try_from(self.signature.as_ref()).expect("Invalid signature")
    }
}
