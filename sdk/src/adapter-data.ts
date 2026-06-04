import { encodeAbiParameters, parseAbiParameters, type Address, type Hex } from "viem";

export function encodePaymasterData(
    adapter: Address,
    adapterData: Hex
) {
    return encodeAbiParameters(
        parseAbiParameters("(address adapter, bytes adapterData)"),
        [{ adapter, adapterData }]
    );
}

export function encodeTornadoAdapterData(
    proof: Hex,
    root: Hex,
    nullifierHash: Hex,
    recipient: Address,
    relayer: Address,
    fee: bigint,
    refund: bigint
) {
    return encodeAbiParameters(
        parseAbiParameters("(bytes proof, bytes32 root, bytes32 nullifierHash, address recipient, address relayer, uint256 fee, uint256 refund)"),
        [{
            proof,
            root,
            nullifierHash,
            recipient,
            relayer,
            fee,
            refund,
        }]
    );
}
