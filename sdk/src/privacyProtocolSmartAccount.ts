import { encodeFunctionData, toHex, type Address, type Hex, type PublicClient } from "viem";
import { entryPoint09Abi, type BundlerClient } from "viem/account-abstraction";

const privacyAccountAbi = [
    {
        type: "function",
        name: "execute",
        inputs: [
            { name: "unshieldCalldata", type: "bytes" },
            {
                name: "tail",
                type: "tuple[]",
                components: [
                    { name: "target", type: "address" },
                    { name: "data", type: "bytes" },
                ],
            },
        ],
        outputs: [],
        stateMutability: "nonpayable",
    },
] as const;

export interface OperationInfo {
    tail: { target: Address; value: bigint; data: Hex }[];
    paymaster: Address;
    callGasLimit: bigint;
    verificationGasLimit: bigint;
    preVerificationGas: bigint;
    maxFeePerGas: bigint;
    maxPriorityFeePerGas: bigint;
    paymasterVerificationGasLimit: bigint;
    paymasterPostOpGasLimit: bigint;
    paymasterData: Hex;
}

export class PrivacyBundler {
    constructor(
        private client: PublicClient,
        private bundlerClient: BundlerClient,
        private sender: Address,
        private entryPoint: Address,
    ) { }

    async sendOperation(
        unshieldCalldata: Hex,
        op: OperationInfo,
    ): Promise<Hex> {
        const callData = encodeFunctionData({
            abi: privacyAccountAbi,
            functionName: "execute",
            args: [unshieldCalldata, op.tail],
        });

        const nonce = await this.client.readContract({
            address: this.entryPoint,
            abi: entryPoint09Abi,
            functionName: "getNonce",
            args: [this.sender, 0n],
        })

        return this.bundlerClient.request({
            method: "eth_sendUserOperation",
            params: [
                {
                    sender: this.sender,
                    nonce: toHex(nonce),
                    callData,
                    callGasLimit: toHex(op.callGasLimit),
                    verificationGasLimit: toHex(op.verificationGasLimit),
                    preVerificationGas: toHex(op.preVerificationGas),
                    maxFeePerGas: toHex(op.maxFeePerGas),
                    maxPriorityFeePerGas: toHex(op.maxPriorityFeePerGas),
                    paymaster: op.paymaster,
                    paymasterVerificationGasLimit: toHex(op.paymasterVerificationGasLimit),
                    paymasterPostOpGasLimit: toHex(op.paymasterPostOpGasLimit),
                    paymasterData: op.paymasterData,
                    signature: "0x",
                },
                this.entryPoint,
            ]
        })
    }
}
