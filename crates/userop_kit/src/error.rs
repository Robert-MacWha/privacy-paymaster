/// Errors from the bundler SDK.
#[derive(Debug, thiserror::Error)]
pub enum BundlerError {
    #[error("Transport error: {0}")]
    Transport(#[source] alloy_provider::transport::TransportError),

    #[error("Abi error: {0}")]
    Abi(#[source] alloy_sol_types::Error),
}
