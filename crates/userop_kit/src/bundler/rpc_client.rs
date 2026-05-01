use reqwest::Client;
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::json;
use std::sync::atomic::{AtomicU64, Ordering};

pub struct RpcClient {
    client: Client,
    url: reqwest::Url,
    id: AtomicU64,
}

#[derive(Debug, thiserror::Error)]
pub enum RpcClientError {
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("RPC error {code}: {message}")]
    Rpc { code: i64, message: String },
    #[error("Missing result")]
    MissingResult,
}

#[derive(Deserialize)]
struct RpcResponse<T> {
    result: Option<T>,
    error: Option<RpcError>,
}

#[derive(Debug, Deserialize)]
struct RpcError {
    code: i64,
    message: String,
}

impl RpcClient {
    pub fn new(url: reqwest::Url) -> Self {
        Self {
            client: Client::new(),
            url,
            id: AtomicU64::new(1),
        }
    }

    pub async fn request<P, R>(&self, method: &str, params: P) -> Result<R, RpcClientError>
    where
        P: Serialize,
        R: DeserializeOwned,
    {
        let id = self.id.fetch_add(1, Ordering::Relaxed);
        let body = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        });

        let resp: RpcResponse<R> = self
            .client
            .post(self.url.clone())
            .json(&body)
            .send()
            .await?
            .json()
            .await?;

        if let Some(err) = resp.error {
            return Err(RpcClientError::Rpc {
                code: err.code,
                message: err.message,
            });
        }

        resp.result.ok_or(RpcClientError::MissingResult)
    }
}
