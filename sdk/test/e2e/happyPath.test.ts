/**
 * E2E test: submits the same UserOp as PrivacyPaymaster.fork.t.sol `test_happyPath`
 * to a locally-running alto bundler as a sanity check of the full broadcast path.
 *
 * Prerequisites: run `just e2e` (or `just setup-e2e` after `just dev`).
 * All on-chain state is prepared by `just setup-e2e` — no beforeAll needed here.
 */
import { expect, test } from "bun:test";
import {
  createPublicClient,
  encodeFunctionData,
  http,
  parseAbi,
  toHex,
  type Address,
  type Hex,
} from "viem";
import { anvil } from "viem/chains";

const ENTRY_POINT_ADDR = "0x433709009B8330FDa32311DF1C2AFA402eD8D009" as Address;
const TORNADO_INSTANCE_ADDR = "0x8cc930096B4Df705A007c4A039BDFA1320Ed2508" as Address;
const DEPLOYER_PK = "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6" as Hex;
const PAYMASTER_ADDR = "0x2C6ddd76DD36CDdE9CB967a8ae66767b456EB1Ba" as Address;

// Relayer param — must be non-zero, matches proof fixtures
const DESTINATION = "0x0000000000000000000000000000000000C0FFEE" as Address;

const ROOT =
  "0x1e199a665f91de139e4c5962d3b31baf8967f7576616a27856048fd1d0a1126f" as Hex;
const NULLIFIER_HASH =
  "0x1e8f3b936b467eb40879f124a156eede9aa5376a0d070e484da270a2a4d1f64e" as Hex;
const PROOF_PM: Hex =
  "0x1b9ec53cee699564a03425760dde645b9efd762c19316dbc20de0319c01445b22d491c87aad3ef66e5f5789c1016eb804ebe116bf8a6aaff35ffafed8c079a510128c3f930d2060fdfaf7214a4a404eb509ea776a3d83bb3c13a2e2c9569e30c2acde37825b0b7cfb678a98800ce143f35989264773899f683c215a2501075a523f309c8baf30a558f36da78cd5ee77e510b526437e6b30a0dd2fa8332057c7b176da03cdab5977a46f65dc902b683e367d34e6fcb0e3f8f577ade4c0ed959332d53dd82c338f3acf30a0e796bc5d03a037ebe1e97b5ef8b1a2ba6a8932d0624164f483e71b02bc52ecb3c89ffedb111ccabc50c606c4d8bd765fece7734600f";

const BUNDLER_URL = "http://localhost:4337";
const ANVIL_URL = "http://localhost:8545";

// ----- Minimal ABI fragments -----
const entryPointAbi = parseAbi([
  "function getNonce(address sender, uint192 key) view returns (uint256 nonce)",
]);

const tornadoAbi = parseAbi([
  "function withdraw(bytes proof, bytes32 root, bytes32 nullifierHash, address recipient, address relayer, uint256 fee, uint256 refund)",
  "function nullifierHashes(bytes32 nullifierHash) view returns (bool)",
  "function denomination() view returns (uint256)",
]);

const privacyAccountAbi = parseAbi([
  "function execute(bytes unshieldCalldata, (address target, bytes data)[] tail)",
]);

// ----- Client -----
const publicClient = createPublicClient({
  chain: anvil,
  transport: http(ANVIL_URL),
});

// ===== Test =====

test(
  "UserOp submitted via alto bundler is included and succeeds",
  async () => {
    const denomination = await publicClient.readContract({
      address: TORNADO,
      abi: tornadoAbi,
      functionName: "denomination",
    });

    const nonce = await publicClient.readContract({
      address: ENTRY_POINT,
      abi: entryPointAbi,
      functionName: "getNonce",
      args: [TORNADO_ACCT_ADDR, 0n],
    });

    // IPrivacyAccount.execute(unshieldCalldata, [])
    // recipient = PAYMASTER_ADDR (proof-committed), relayer = DESTINATION
    const unshieldCalldata = encodeFunctionData({
      abi: tornadoAbi,
      functionName: "withdraw",
      args: [PROOF_PM, ROOT, NULLIFIER_HASH, PAYMASTER_ADDR, DESTINATION, 0n, 0n],
    });
    const callData = encodeFunctionData({
      abi: privacyAccountAbi,
      functionName: "execute",
      args: [unshieldCalldata, []],
    });

    // ERC-4337 v0.7 JSON-RPC UserOperation (separate fields, not packed)
    const userOp = {
      sender: TORNADO_ACCT_ADDR,
      nonce: toHex(nonce),
      callData,
      callGasLimit: toHex(1_500_000),
      verificationGasLimit: toHex(500_000),
      preVerificationGas: toHex(100_000),
      maxFeePerGas: toHex(10_000_000_000), // 10 gwei
      maxPriorityFeePerGas: toHex(1_000_000_000),  // 1 gwei
      paymaster: PAYMASTER_ADDR,
      paymasterVerificationGasLimit: toHex(300_000),
      paymasterPostOpGasLimit: toHex(100_000),
      paymasterData: "0x",
      signature: "0x",
    };

    // Submit to bundler
    const sendRes = await fetch(BUNDLER_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_sendUserOperation",
        params: [userOp, ENTRY_POINT],
      }),
    });
    const sendBody = (await sendRes.json()) as {
      result?: string;
      error?: { code: number; message: string };
    };
    expect(
      sendBody.error,
      `eth_sendUserOperation error: ${JSON.stringify(sendBody.error)}`,
    ).toBeUndefined();
    const userOpHash = sendBody.result!;

    // Poll for receipt (max 30 s)
    let receipt: { success: boolean } | null = null;
    for (let i = 0; i < 30; i++) {
      await new Promise((r) => setTimeout(r, 1000));
      const r = await fetch(BUNDLER_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 2,
          method: "eth_getUserOperationReceipt",
          params: [userOpHash],
        }),
      });
      const body = (await r.json()) as { result: { success: boolean } | null };
      if (body.result !== null) { receipt = body.result; break; }
    }

    expect(receipt, "no receipt after 30 s").not.toBeNull();
    expect(receipt!.success).toBe(true);

    // Nullifier is marked spent
    const nullifierSpent = await publicClient.readContract({
      address: TORNADO,
      abi: tornadoAbi,
      functionName: "nullifierHashes",
      args: [NULLIFIER_HASH],
    });
    expect(nullifierSpent).toBe(true);

    // Destination received (denomination - fee)
    const destBalance = await publicClient.getBalance({ address: DESTINATION });
    expect(destBalance, "destination received nothing").toBeGreaterThan(0n);
    expect(destBalance, "fee was zero").toBeLessThan(denomination);

    // Paymaster kept the fee; full denomination is conserved
    const pmBalance = await publicClient.getBalance({ address: PAYMASTER_ADDR });
    expect(pmBalance + destBalance, "fee accounting mismatch").toBe(denomination);
  },
  60_000,
);
