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
  private op: Partial<UserOperation> & { sender: Address };
  private nonceKey: bigint = 0n;
  private gas: GasConfig = { type: 'auto' };

  constructor(sender: Address) {
    this.op = {
      sender,
      callData: '0x',
      signature: '0x',
    };
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
    this.gas = gas;
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

    this.op.callGasLimit = 0n;
    this.op.verificationGasLimit = 0n;
    this.op.preVerificationGas = 0n;
    this.op.maxFeePerGas = 0n;
    this.op.maxPriorityFeePerGas = 0n;
    this.op.paymasterVerificationGasLimit = 0n;
    this.op.paymasterPostOpGasLimit = 0n;

    if (this.gas.type === 'auto') {
      const [est, gasPrice] = await Promise.all([
        bundlerClient.estimateUserOperationGas(this.op as UserOperation),
        bundlerClient.getUserOperationGasPrice(),
      ]);
      this.op.callGasLimit = BigInt(est.callGasLimit);
      this.op.verificationGasLimit = BigInt(est.verificationGasLimit);
      this.op.preVerificationGas = BigInt(est.preVerificationGas);
      this.op.maxFeePerGas = BigInt(gasPrice.fast.maxFeePerGas);
      this.op.maxPriorityFeePerGas = BigInt(gasPrice.fast.maxPriorityFeePerGas);
      this.op.paymasterVerificationGasLimit = est.paymasterVerificationGasLimit ? BigInt(est.paymasterVerificationGasLimit) : undefined;
      this.op.paymasterPostOpGasLimit = est.paymasterPostOpGasLimit ? BigInt(est.paymasterPostOpGasLimit) : undefined;
    } else {
      this.op.callGasLimit = this.gas.callGasLimit;
      this.op.verificationGasLimit = this.gas.verificationGasLimit;
      this.op.preVerificationGas = this.gas.preVerificationGas;
      this.op.maxFeePerGas = this.gas.maxFeePerGas;
      this.op.maxPriorityFeePerGas = this.gas.maxPriorityFeePerGas;
      this.op.paymasterVerificationGasLimit = this.gas.paymasterVerificationGasLimit;
      this.op.paymasterPostOpGasLimit = this.gas.paymasterPostOpGasLimit;
    }

    return this.op as UserOperation;
  }
}
