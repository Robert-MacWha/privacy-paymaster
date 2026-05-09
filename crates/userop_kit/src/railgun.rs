use alloy::{
    eips::eip7702::{Authorization, SignedAuthorization},
    primitives::{Address, B128, Bytes, U256, address, aliases::U120},
    signers::Signer,
    sol_types::{SolCall, SolValue},
};

use crate::{UserOperationBuilder, abis::privacy_account::IPrivacyAccount};

pub struct RailgunProtocol {
    fee_calldata: Bytes,
    tail_calls: Vec<IPrivacyAccount::Call>,
}

pub const IMPL: Address = address!("0xaBAd4109fcF3edBf7B7Cdff37A43a2197B5f2cC9");
pub const PAYMASTER: Address = address!("0xBbbc86034C5371e098163A39eC1bb8B2f015bB74");

// TODO: Add helper function for constructing a new Builder fomr (sender: Address, fee_transaction: RailgunSmartWallet::Transaction)
impl UserOperationBuilder<RailgunProtocol> {
    /// Create a new Railgun UserOperationBuilder with the given sender and fee transaction calldata.
    ///
    /// fee_calldata should be the RailgunSmartWallet::transactCall::abi_encode((fee_transaction)) containing
    /// a single transaction that pays the fee.
    pub fn new_railgun(fee_calldata: Bytes, random: B128, asset: Address, value: u128) -> Self {
        let protocol = RailgunProtocol {
            fee_calldata,
            tail_calls: Vec::new(),
        };

        let builder = UserOperationBuilder::new_with(protocol)
            .with_paymaster(PAYMASTER)
            .with_paymaster_data(
                (random, asset, U120::saturating_from(value))
                    .abi_encode()
                    .into(),
            );
        builder.update_calldata()
    }

    pub fn with_tail_calls(mut self, calls: Vec<IPrivacyAccount::Call>) -> Self {
        self.protocol.tail_calls = calls;
        self.update_calldata()
    }

    fn update_calldata(self) -> Self {
        let fee_call = self.protocol.fee_calldata.clone();
        let calldata =
            IPrivacyAccount::executeCall::new((fee_call, self.protocol.tail_calls.clone()))
                .abi_encode()
                .into();
        self.with_calldata(calldata)
    }
}

/// Creates and signs a Railgun authorization for the given signer, chain ID, and nonce,
/// setting the address to the standard Railgun withdrawer impl.
pub async fn sign_railgun_authorization(
    signer: &impl Signer,
    chain_id: u64,
    nonce: u64,
) -> Result<SignedAuthorization, alloy::signers::Error> {
    let auth = railgun_authorization(chain_id, nonce);
    let sig = signer.sign_hash(&auth.signature_hash()).await?;
    Ok(auth.into_signed(sig))
}

/// Creates a Railgun authorization for the given chain ID and nonce,
/// setting the address to the standard Railgun withdrawer impl.
pub fn railgun_authorization(chain_id: u64, nonce: u64) -> Authorization {
    Authorization {
        chain_id: U256::from(chain_id),
        address: IMPL,
        nonce,
    }
}
