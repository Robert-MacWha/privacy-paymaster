
## Architecture

The paymaster validates the user's ZK proof and nullifier during `validatePaymasterUserOp`. If validation passes, the paymaster is committed to paying gas. During execution, the paymaster withdraws the note, deducts a fee, and forwards the remainder to the user's destination. The key insight is that proof validation is strictly cheaper than note creation, making griefing economically unprofitable.

### Happy Path
```mermaid
sequenceDiagram
    participant User
    participant Bundler
    participant EntryPoint
    participant Paymaster
    participant PrivacyProtocol
 
    User->>Bundler: Submit userOp
    Note over Bundler: Simulation phase
 
    Bundler->>EntryPoint: simulateValidation()
    EntryPoint->>Paymaster: validatePaymasterUserOp()
    Paymaster->>PrivacyProtocol: fetch state()
    Note over Paymaster: Verify receiver == paymaster
    Note over Paymaster: Verify Nullifier unused
    Note over Paymaster: Verify proof
    Paymaster-->>EntryPoint: validation success
    EntryPoint-->>Bundler: simulation passes
 
    Note over Bundler: Execution phase
 
    Bundler->>EntryPoint: handleOps()
    Note over EntryPoint: _tryDecrementDeposit()
    EntryPoint->>Paymaster: validatePaymasterUserOp()
    Note over Paymaster: Repeat Validation
    Paymaster-->>EntryPoint: validation success
 
    EntryPoint->>Paymaster: execution()
    Paymaster->>PrivacyProtocol: execute operation()
    PrivacyProtocol-->>Paymaster: Withdrawal received
    Paymaster-->>EntryPoint: execution success
    EntryPoint->>Paymaster: postOp()
    Note over Paymaster: Deduct fee
    Paymaster->>User: Pay remainder
    Paymaster-->>EntryPoint: postOp success
    EntryPoint-->>Bundler: handleOps success
```

### Invalid Proof
```mermaid
sequenceDiagram
    participant Attacker
    participant Bundler
    participant EntryPoint
    participant Paymaster
 
    Attacker->>Bundler: Submit userOp
    Note over Bundler: Simulation phase
 
    Bundler->>EntryPoint: simulateValidation()
    EntryPoint->>Paymaster: validatePaymasterUserOp()
    Note over Paymaster: Verify receiver == paymaster
    Note over Paymaster: Verify Nullifier unused
    Note over Paymaster: Invalid Proof
    Paymaster-->>EntryPoint: revert
    EntryPoint-->>Bundler: revert
    
    Note over Bundler: Cost: 0
```

### Nullifier Frontrun (Griefing the Bundler)

Only viable if the bundler's transaction can be frontran.

```mermaid
sequenceDiagram
    participant Attacker
    participant Bundler
    participant EntryPoint
    participant Paymaster
    participant PrivacyProtocol
 
    Attacker->>Bundler: Submit userOp
    Note over Bundler: Simulation phase
 
    Bundler->>EntryPoint: simulateValidation()
    EntryPoint->>Paymaster: validatePaymasterUserOp()
    Paymaster->>PrivacyProtocol: fetch state()
    Note over Paymaster: Verify receiver == paymaster
    Note over Paymaster: Verify Nullifier unused
    Note over Paymaster: Verify proof
    Paymaster-->>EntryPoint: validation success
    EntryPoint-->>Bundler: simulation passes
 
    Note over Bundler: Execution phase

    Note over Attacker: Frontrun `handleOps()`
    Attacker->>PrivacyProtocol: withdraw()
    Note over PrivacyProtocol: Proof now invalid
 
    Bundler->>EntryPoint: handleOps()
    Note over EntryPoint: _tryDecrementDeposit()
    EntryPoint->>Paymaster: validatePaymasterUserOp()
    Note over Paymaster: Validation Fails
    Paymaster-->>EntryPoint: revert
    EntryPoint-->>Bundler: revert
    
    Note over Bundler: Cost: Variable
```
