import { createPublicClient, custom, type Address, type Hex, type SignedAuthorization } from 'viem';
import type { UserOperation } from 'viem';
import type { EIP1193Provider, GasConfig } from './types.js';
import type { BundlerClient } from './bundlerClient.js';

const entryPointAbi = [
  {
    type: 'function',
    name: 'getNonce',
    inputs: [
      { name: 'sender', type: 'address' },
      { name: 'key', type: 'uint192' },
    ],
    outputs: [{ name: 'nonce', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const;

export class UserOperationBuilder {
  private op: UserOperation;
  private nonceKey: bigint = 0n;
  private autoGas: boolean = true;

  constructor(sender: Address) {
    this.op = {
      sender,
      nonce: 0n,
      callData: '0x',
      callGasLimit: 0n,
      verificationGasLimit: 0n,
      preVerificationGas: 0n,
      maxFeePerGas: 0n,
      maxPriorityFeePerGas: 0n,
      signature: '0x',
    } as UserOperation;
  }

  withCalldata(calldata: Hex): this {
    this.op.callData = calldata;
    return this;
  }

  withPaymaster(paymaster: Address): this {
    this.op.paymaster = paymaster;
    return this;
  }

  withPaymasterData(data: Hex): this {
    this.op.paymasterData = data;
    return this;
  }

  withSignature(signature: Hex): this {
    this.op.signature = signature;
    return this;
  }

  withNonceKey(key: bigint): this {
    this.nonceKey = key;
    return this;
  }

  withGas(gas: GasConfig): this {
    if (gas.type === 'manual') {
      this.autoGas = false;
      this.op.callGasLimit = gas.callGasLimit;
      this.op.verificationGasLimit = gas.verificationGasLimit;
      this.op.preVerificationGas = gas.preVerificationGas;
      this.op.maxFeePerGas = gas.maxFeePerGas;
      this.op.maxPriorityFeePerGas = gas.maxPriorityFeePerGas;
      this.op.paymasterVerificationGasLimit = gas.paymasterVerificationGasLimit;
      this.op.paymasterPostOpGasLimit = gas.paymasterPostOpGasLimit;
    } else {
      this.autoGas = true;
    }
    return this;
  }

  withFactory(factory: Address, factoryData: Hex): this {
    this.op.factory = factory;
    this.op.factoryData = factoryData;
    return this;
  }

  withAuthorization(auth: SignedAuthorization<number>): this {
    this.op.authorization = auth;
    return this;
  }

  async build(
    provider: EIP1193Provider,
    bundlerClient: BundlerClient,
  ): Promise<UserOperation> {
    const rpcClient = createPublicClient({ transport: custom(provider) });

    this.op.nonce = await rpcClient.readContract({
      address: bundlerClient.entryPoint,
      abi: entryPointAbi,
      functionName: 'getNonce',
      args: [this.op.sender, this.nonceKey],
    });

    if (this.autoGas) {
      const [est, gasPrice] = await Promise.all([
        bundlerClient.estimateUserOperationGas(this.op),
        bundlerClient.getUserOperationGasPrice(),
      ]);
      this.op.callGasLimit = BigInt(est.callGasLimit);
      this.op.verificationGasLimit = BigInt(est.verificationGasLimit);
      this.op.preVerificationGas = BigInt(est.preVerificationGas);
      this.op.maxFeePerGas = BigInt(gasPrice.fast.maxFeePerGas);
      this.op.maxPriorityFeePerGas = BigInt(gasPrice.fast.maxPriorityFeePerGas);
      this.op.paymasterVerificationGasLimit = est.paymasterVerificationGasLimit ? BigInt(est.paymasterVerificationGasLimit) : undefined;
      this.op.paymasterPostOpGasLimit = est.paymasterPostOpGasLimit ? BigInt(est.paymasterPostOpGasLimit) : undefined;
    }

    return this.op;
  }
}
