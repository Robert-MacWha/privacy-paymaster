import type { Address, Hex, PublicClient, UserOperation } from 'viem';
import type { GasConfig } from './types.js';
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
  private calldata: Hex = '0x';
  private paymaster?: Address;
  private paymasterData?: Hex;
  private signature: Hex = '0x';
  private nonceKey: bigint = 0n;
  private gas: GasConfig = { type: 'auto' };
  private factory?: Address;
  private factoryData?: Hex;

  constructor(
    private sender: Address,
  ) { }

  withCalldata(calldata: Hex): this {
    this.calldata = calldata;
    return this;
  }

  withPaymaster(paymaster: Address): this {
    this.paymaster = paymaster;
    return this;
  }

  withPaymasterData(data: Hex): this {
    this.paymasterData = data;
    return this;
  }

  withSignature(signature: Hex): this {
    this.signature = signature;
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
    this.factory = factory;
    this.factoryData = factoryData;
    return this;
  }

  async build(
    rpcClient: PublicClient,
    bundlerClient: BundlerClient,
  ): Promise<UserOperation> {
    const nonce = await rpcClient.readContract({
      address: bundlerClient.entryPoint,
      abi: entryPointAbi,
      functionName: 'getNonce',
      args: [this.sender, this.nonceKey],
    });

    const skeleton: UserOperation = {
      sender: this.sender,
      nonce,
      factory: this.factory,
      factoryData: this.factoryData,
      callData: this.calldata,
      callGasLimit: 0n,
      verificationGasLimit: 0n,
      preVerificationGas: 0n,
      maxFeePerGas: 0n,
      maxPriorityFeePerGas: 0n,
      paymaster: this.paymaster,
      paymasterVerificationGasLimit: 0n,
      paymasterPostOpGasLimit: 0n,
      paymasterData: this.paymasterData,
      signature: this.signature,
    };

    if (this.gas.type === 'auto') {
      const [est, gasPrice] = await Promise.all([
        bundlerClient.estimateUserOperationGas(skeleton),
        bundlerClient.getUserOperationGasPrice(),
      ]);
      skeleton.callGasLimit = BigInt(est.callGasLimit);
      skeleton.verificationGasLimit = BigInt(est.verificationGasLimit);
      skeleton.preVerificationGas = BigInt(est.preVerificationGas);
      skeleton.maxFeePerGas = BigInt(gasPrice.fast.maxFeePerGas);
      skeleton.maxPriorityFeePerGas = BigInt(gasPrice.fast.maxPriorityFeePerGas);
      skeleton.paymasterVerificationGasLimit = est.paymasterVerificationGasLimit ? BigInt(est.paymasterVerificationGasLimit) : undefined;
      skeleton.paymasterPostOpGasLimit = est.paymasterPostOpGasLimit ? BigInt(est.paymasterPostOpGasLimit) : undefined;
    } else {
      skeleton.callGasLimit = this.gas.callGasLimit;
      skeleton.verificationGasLimit = this.gas.verificationGasLimit;
      skeleton.preVerificationGas = this.gas.preVerificationGas;
      skeleton.maxFeePerGas = this.gas.maxFeePerGas;
      skeleton.maxPriorityFeePerGas = this.gas.maxPriorityFeePerGas;
      skeleton.paymasterVerificationGasLimit = this.gas.paymasterVerificationGasLimit;
      skeleton.paymasterPostOpGasLimit = this.gas.paymasterPostOpGasLimit;
    }

    return skeleton;
  }
}
