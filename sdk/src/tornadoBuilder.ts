import { encodeFunctionData, parseAbi, type Address, type Hex } from "viem";
import { PrivacyProtocolBuilder } from "./privacyProtocolBuilder";

export const tornadoAbi = parseAbi([
    "function withdraw(bytes proof, bytes32 root, bytes32 nullifierHash, address recipient, address relayer, uint256 fee, uint256 refund)",
]);

export class TornadoBuilder extends PrivacyProtocolBuilder {
    constructor(
        sender: Address,
    ) {
        super(sender);
    }

    withWithdraw(
        proof: Hex,
        root: Hex,
        nullifierHash: Hex,
        recipient: Address,
        relayer: Address,
        fee: bigint,
    ) {
        const calldata = encodeFunctionData({
            abi: tornadoAbi,
            functionName: "withdraw",
            args: [proof, root, nullifierHash, recipient, relayer, fee, 0n],
        });
        return this.withUnshieldCalldata(calldata);
    }
}