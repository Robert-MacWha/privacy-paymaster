use alloy_primitives::Bytes;
use alloy_sol_types::SolCall;

use crate::{UserOperationBuilder, abis::privacy_account::IPrivacyAccount};

pub struct TornadoCashProtocol {
    withdraw_calldata: Bytes,
    tail_calls: Vec<IPrivacyAccount::Call>,
}

// TODO: Add helper function for constructing a new Builder fomr (sender: Address, withdrawal: Tornado::withdrawCall)
impl UserOperationBuilder<TornadoCashProtocol> {
    /// Create a new Tornado Cash UserOperationBuilder with the given sender and withdraw calldata.
    ///
    /// withdraw_calldata should be `Tornado::withdrawCall::abi_encode((proof, root, nullifierHash, recipient, relayer, fee, refund))`
    pub fn new_tornadocash(withdraw_calldata: Bytes) -> Self {
        let protocol = TornadoCashProtocol {
            withdraw_calldata,
            tail_calls: Vec::new(),
        };

        let builder = UserOperationBuilder::new_with(protocol);
        builder.update_calldata()
    }

    pub fn with_tail_calls(mut self, calls: Vec<IPrivacyAccount::Call>) -> Self {
        self.protocol.tail_calls = calls;
        self.update_calldata()
    }

    fn update_calldata(self) -> Self {
        let calldata = IPrivacyAccount::executeCall::new((
            self.protocol.withdraw_calldata.clone(),
            self.protocol.tail_calls.clone(),
        ))
        .abi_encode()
        .into();
        self.with_calldata(calldata)
    }
}
