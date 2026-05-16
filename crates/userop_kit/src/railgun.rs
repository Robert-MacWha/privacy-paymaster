use alloy::{
    eips::eip7702::Authorization,
    primitives::{Address, B128, B256, Bytes, U256, address, aliases::U120, b256},
    sol_types::{SolCall, SolValue},
};

use crate::{
    abis::privacy_account::IPrivacyAccount,
    builder::UserOperationBuilder,
    entry_point::{ENTRY_POINT_08, entry_point_08_domain},
};

pub struct RailgunProtocol {
    fee_calldata: Bytes,
    tail_calls: Vec<IPrivacyAccount::Call>,
}

/// Railgun 7702 Sender implementation address on all chains.
///
/// This is the only implementation that the Privacy-Protocol paymaster supports for
/// railgun user operations.
pub const IMPL: Address = address!("0xaBAd4109fcF3edBf7B7Cdff37A43a2197B5f2cC9");

/// Privacy-Protocol paymaster address on all chains.
pub const PAYMASTER: Address = address!("0xBbbc86034C5371e098163A39eC1bb8B2f015bB74");

/// EntryPoint 0.8 address on all chains.
pub const ENTRY_POINT: Address = ENTRY_POINT_08;

/// Railgun paymaster master public key.
pub const PAYMASTER_MASTER_PUBLIC_KEY: B256 =
    b256!("0x19acdde26147205d58fd7768be7c011f08a147ef86e6b70968d09c81cef74b13");

/// Railgun paymaster viewing public key.
pub const PAYMASTER_VIEWING_PUBLIC_KEY: B256 =
    b256!("0x63ec4d326fc49c1c71064c982fb0bcbca2ba593b44ff7e8c7e4e75b401ae1d9c");

impl UserOperationBuilder<RailgunProtocol> {
    /// Create a new Railgun UserOperationBuilder with the given sender and fee transaction calldata.
    ///
    /// `auth_nonce` is the 7702 authorization nonce, which must match the EOA's current transaction
    /// nonce when the authorization is consumed.
    ///
    /// `fee_calldata`` should be the `RailgunSmartWallet::transactCall::abi_encode((fee_transaction))` containing
    /// a single transaction that pays the fee.
    ///
    /// ? Accepts `fee_calldata: Bytes` instead of `RailgunSmartWallet::transactCall` so the caller
    /// isn't forced to use our `userop_kit::abis::railgun::RailgunSmartWallet::transactCall` struct
    /// for their fee transaction.
    pub fn new_railgun(
        chain_id: u64,
        sender: Address,
        auth_nonce: u64,
        fee_calldata: Bytes,
        random: B128,
        asset: Address,
        value: u128,
    ) -> Self {
        let auth = Authorization {
            chain_id: U256::from(chain_id),
            address: IMPL,
            nonce: auth_nonce,
        };

        let protocol = RailgunProtocol {
            fee_calldata,
            tail_calls: Vec::new(),
        };

        let domain = entry_point_08_domain(chain_id);
        let builder = UserOperationBuilder::new_with(sender, ENTRY_POINT, domain, protocol)
            .with_paymaster(PAYMASTER)
            .with_authorization(auth)
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
