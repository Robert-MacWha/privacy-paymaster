import { http, toHex, type Address, type EstimateUserOperationGasReturnType, type Hash } from "viem";
import type { UserOperation, UserOperationReceipt, BundlerClient as ViemBundlerClient } from "viem/account-abstraction";
import { createBundlerClient as createViemBundlerClient } from "viem/account-abstraction";

export type UserOperationGasPrice = {
    slow: GasPrice;
    standard: GasPrice;
    fast: GasPrice;
};

export type GasPrice = {
    maxFeePerGas: bigint;
    maxPriorityFeePerGas: bigint;
};

export class BundlerClient {
    private client: ViemBundlerClient;

    constructor(bundlerUrl: string, public entryPoint: Address) {
        this.client = createViemBundlerClient({ transport: http(bundlerUrl) });
    }

    async estimateUserOperationGas(op: UserOperation): Promise<EstimateUserOperationGasReturnType> {
        this.client.estimateUserOperationGas

        return this.client.request({
            method: "eth_estimateUserOperationGas",
            params: [
                {
                    sender: op.sender,
                    nonce: toHex(op.nonce),
                    callData: op.callData,
                    callGasLimit: toHex(0),
                    verificationGasLimit: toHex(0),
                    preVerificationGas: toHex(0),
                    maxFeePerGas: toHex(0),
                    maxPriorityFeePerGas: toHex(0),
                    paymaster: op.paymaster,
                    paymasterVerificationGasLimit: op.paymaster ? toHex(0) : undefined,
                    paymasterPostOpGasLimit: op.paymaster ? toHex(0) : undefined,
                    paymasterData: op.paymasterData,
                    signature: op.signature,
                    eip7702Auth: op.authorization ? serializeAuth(op.authorization) : undefined,
                },
                this.entryPoint
            ],
        })
    }

    async getUserOperationGasPrice(): Promise<UserOperationGasPrice> {
        const result = await this.client.request({
            method: "pimlico_getUserOperationGasPrice",
            params: [],
        } as any);

        const parse = (tier: any): GasPrice => ({
            maxFeePerGas: BigInt(tier.maxFeePerGas),
            maxPriorityFeePerGas: BigInt(tier.maxPriorityFeePerGas),
        });

        return {
            slow: parse((result as any).slow),
            standard: parse((result as any).standard),
            fast: parse((result as any).fast),
        };
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
                    eip7702Auth: op.authorization ? serializeAuth(op.authorization) : undefined,
                },
                this.entryPoint,
            ]
        })
    }

    async waitForUserOperationReceipt(hash: Hash): Promise<UserOperationReceipt> {
        return this.client.waitForUserOperationReceipt({ hash });
    }
}

function serializeAuth(auth: NonNullable<UserOperation['authorization']>) {
    return {
        address: auth.address,
        chainId: toHex(auth.chainId),
        nonce: toHex(auth.nonce),
        r: auth.r,
        s: auth.s,
        yParity: toHex(auth.yParity!),
    };
}
