import { encodeFunctionData, type Address, type Hex } from "viem";
import { UserOperationBuilder } from "./builder";

const privacyAccountAbi = [
    {
        type: "function",
        name: "execute",
        inputs: [
            { name: "feeCalldata", type: "bytes" },
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

export class PrivacyProtocolBuilder extends UserOperationBuilder {
    private feeCalldata: Hex = "0x";
    private tail: { target: Address; data: Hex }[] = [];

    constructor(
        sender: Address,
    ) {
        super(sender);
    }

    withFeeCalldata(calldata: Hex) {
        this.feeCalldata = calldata;
        const cd = encodeFunctionData({
            abi: privacyAccountAbi,
            functionName: "execute",
            args: [this.feeCalldata, this.tail],
        });

        return this.withCalldata(cd);
    }

    withTailCall(target: Address, data: Hex) {
        this.tail.push({ target, data });
        const cd = encodeFunctionData({
            abi: privacyAccountAbi,
            functionName: "execute",
            args: [this.feeCalldata, this.tail],
        });

        return this.withCalldata(cd);
    }
}