use alloy::primitives::{Address, address};
use alloy_sol_types::{Eip712Domain, eip712_domain};

pub const ENTRY_POINT_08: Address = address!("0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108");

pub const fn entry_point_08_domain(chain_id: u64) -> Eip712Domain {
    eip712_domain! {
        name: "ERC4337",
        version: "1",
        chain_id: chain_id,
        verifying_contract: ENTRY_POINT_08,

    }
}
