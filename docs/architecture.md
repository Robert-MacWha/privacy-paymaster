
## Architecture

The paymaster validates the user's ZK proof and nullifier during `validatePaymasterUserOp`. If validation passes, the paymaster is committed to paying gas. During execution, the sender executes the fee-paying operation and any subsequent user-defined tail calls.

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
    Note over Paymaster: Verify sender 7702 impl
    Note over Paymaster: Verify userOp
    Paymaster->>PrivacyProtocol: fetch state()
    Note over Paymaster: Verify feeCalldata
    Note over Paymaster: Verify fee covers gas
    Paymaster-->>EntryPoint: 
    EntryPoint-->>Bundler:
 
    Note over Bundler: Execution phase
 
    Bundler->>EntryPoint: handleOps()
    Note over EntryPoint: Repeat Validation
 
    EntryPoint->>Sender: execution()
    Sender->>PrivacyProtocol: execute feeCalldata() 
    Note over PrivacyProtocol: Pay paymaster's fee
    PrivacyProtocol-->>Sender: 
    Note over Sender: Execute optional tail calls
    Sender-->>EntryPoint: 
    EntryPoint-->>Bundler:
    Bundler-->>User: 
```
