import { toHex, type Address, type Chain, type EstimateUserOperationGasReturnType, type Hash, type Transport } from "viem";
import type { UserOperation, UserOperationReceipt, BundlerClient as ViemBundlerClient } from "viem/account-abstraction";
import { createBundlerClient as createViemBundlerClient } from "viem/account-abstraction";

export class BundlerClient {
    private client: ViemBundlerClient;

    constructor(chain: Chain, transport: Transport, public entryPoint: Address) {
        this.client = createViemBundlerClient({ chain, transport });
    }

    async estimateUserOperationGas(op: UserOperation): Promise<EstimateUserOperationGasReturnType> {
        return this.client.estimateUserOperationGas(op);
    }

    async sendUserOperation(op: UserOperation): Promise<Hash> {
        return this.client.request({
            method: "eth_sendUserOperation",
            params: [
                {
                    sender: op.sender,
                    nonce: toHex(op.nonce),
                    callData: op.callData,
                    callGasLimit: toHex(op.callGasLimit),
                    verificationGasLimit: toHex(op.verificationGasLimit),
                    preVerificationGas: toHex(op.preVerificationGas),
                    maxFeePerGas: toHex(op.maxFeePerGas),
                    maxPriorityFeePerGas: toHex(op.maxPriorityFeePerGas),
                    paymaster: op.paymaster,
                    paymasterVerificationGasLimit: op.paymasterVerificationGasLimit ? toHex(op.paymasterVerificationGasLimit) : undefined,
                    paymasterPostOpGasLimit: op.paymasterPostOpGasLimit ? toHex(op.paymasterPostOpGasLimit) : undefined,
                    paymasterData: op.paymasterData,
                    signature: op.signature,
                },
                this.entryPoint,
            ]
        })
    }

    async waitForUserOperationReceipt(hash: Hash): Promise<UserOperationReceipt> {
        return this.client.waitForUserOperationReceipt({ hash });
    }
}