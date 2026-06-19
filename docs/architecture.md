
## Architecture

The paymaster validates and executes the user's ZK proof during `validatePaymasterUserOp`.

https://mermaid.live/edit

```mermaid
sequenceDiagram
    participant User
    participant Bundler
    participant EntryPoint
    participant Sender
    participant Paymaster
    participant PrivacyProtocol
 
    User->>Bundler: Submit userOp
    Note over Bundler: Simulation phase
 
    Bundler->>EntryPoint: simulateValidation()
    EntryPoint->>Sender: validateUserOp()
    Note over Sender: Verify signature
    Sender-->>EntryPoint:
    EntryPoint->>Paymaster: validatePaymasterUserOp()
    Paymaster->>PrivacyProtocol: executeTransaction()
    PrivacyProtocol: execute feeCalldata() 
    Note over PrivacyProtocol: Pay paymaster's fee
    PrivacyProtocol-->>Sender: 
    Paymaster-->>EntryPoint: 
    EntryPoint-->>Bundler:
 
    Note over Bundler: Execution phase
 
    Bundler->>EntryPoint: handleOps()
    Note over EntryPoint: Repeat Validation
 
    EntryPoint->>Sender: execution()
    Sender-->>EntryPoint: 
    EntryPoint-->>Bundler:
    Bundler-->>User: 
```
