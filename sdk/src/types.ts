export interface EIP1193Provider {
  request(args: { method: string; params?: unknown }): Promise<unknown>;
}

export type GasConfig =
  | { type: 'auto' }
  | {
    type: 'manual';
    callGasLimit: bigint;
    verificationGasLimit: bigint;
    preVerificationGas: bigint;
    maxFeePerGas: bigint;
    maxPriorityFeePerGas: bigint;
    paymasterVerificationGasLimit?: bigint;
    paymasterPostOpGasLimit?: bigint;
  };
