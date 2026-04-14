import { encodeFunctionData, parseAbi, type Address, type Hex } from "viem";
import { type OperationInfo, PrivacyBundler } from "./privacyProtocolSmartAccount";

export const tornadoAbi = parseAbi([
    "function withdraw(bytes proof, bytes32 root, bytes32 nullifierHash, address recipient, address relayer, uint256 fee, uint256 refund)",
]);

export interface TornadoWithdrawParams {
    proof: Hex;
    root: Hex;
    nullifierHash: Hex;
    recipient: Address;
    relayer: Address;
    fee: bigint;
}

export class TornadoBundler {
    constructor(private bundler: PrivacyBundler) { }

    sendWithdraw(params: TornadoWithdrawParams, op: OperationInfo): Promise<Hex> {
        const unshieldCalldata = encodeFunctionData({
            abi: tornadoAbi,
            functionName: "withdraw",
            args: [params.proof, params.root, params.nullifierHash, params.recipient, params.relayer, params.fee, 0n],
        });

        return this.bundler.sendOperation(unshieldCalldata, op);
    }
}
