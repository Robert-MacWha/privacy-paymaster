import { Instance } from "prool";
import { createPublicClient, createWalletClient, http, parseAbi, type Address, type Hex } from "viem";
import { entryPoint09Address } from "viem/account-abstraction";
import { privateKeyToAccount } from "viem/accounts";
import { anvil } from "viem/chains";
import { TornadoBuilder } from "./src/tornadoBuilder";
import { BundlerClient } from "./src/bundlerClient";

const SEPOLIA_RPC_URL: string = process.env.SEPOLIA_RPC_URL!;

const ENTRY_POINT = entryPoint09Address;

// Address the tornado AA20 account is deployed at in the Anvil state dump
const TORNADO_INSTANCE_ADDR = "0x8cc930096B4Df705A007c4A039BDFA1320Ed2508" as Address;

// Arbitrary deployer key for txns.
const PRIVATE_KEY = "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6" as Hex;

// Bundler executor and utility keys (not Anvil defaults, to avoid EIP-7702 delegations on Sepolia)
const EXECUTOR_PK = "0x4a3a02862ddcb260ed52d40ef03f8e3d78fa3d174b0ef333afdf1ffb4a648cd5" as Hex;
const UTILITY_PK = "0xdd4b2564c83ff7de602c39ffda1146055dc1814b07c083d7971722384f1f01a6" as Hex;

// Pre-selected tornadocash public inputs
const RECIPIENT = "0x0000000000000000000000000000000000C0FFEE" as Address;
const PAYMASTER = "0x2C6ddd76DD36CDdE9CB967a8ae66767b456EB1Ba" as Address;
const TORNADO_ACCOUNT = "0xdD14776222FeF5FfAF9F8f4c62653d011CE63A1F" as Address;
const FEE = 50000000000000000n;

// Pre-computed tornadocash proof data from above inputs.
const COMMITMENT = "0x132fa39bc9676c0c89d567ff63a45dd862858f8f75cf8768130c5aa62dae2a5b" as Hex;
const ROOT =
    "0x187ee16dba9869f6319ffd06cc5d7dc0d6b20b66735362bb30bb0b3fe62667bc" as Hex;
const NULLIFIER_HASH =
    "0x08f0366544886c7bb64a8cedd2ec9c78043c69b4c8de426de82b5702c6f5a1e2" as Hex;
const PROOF_VALID: Hex =
    "0x216d0abb7a01ca6b27b698a3c8071c73d01753bf6e4fb60d9c3e7578624df9c20c5aafbebf3338aa9981cc421a0cc97b3cfe48aff4ad9e8d081b7d1a3715fb0521abfb49e30d5b82de52a37992b204a642a8adfe89e0c8e7f1b13ca84e034a1e1a3302fd6ce746f4688eae970ead8dc728cafa84de6ab2af51bcd1d4bf70e058197d081399eb8759fcbf97d6beb5f15a599c9edb3cc13884ebfe082a87f94bcd1afddca40c3ba493fa7807c3d031ab8a3b70437cd0a2651bf2a29d73753776612928c8c8836949883a0f86e4606a2873ab0abc4660159c8f6ee2c2100f01226e269ae5b493d4744009e26a349ed7de832ec6b2a86416f31b3fee5f473c41341c";

const tornadoAbi = parseAbi([
    "function deposit(bytes32 _commitment) external payable",
    "function denomination() external view returns(uint256)",
]);

const { execRpcUrl, bundlerRpcUrl, stop } = await startServers(SEPOLIA_RPC_URL);

try {
    const publicClient = createPublicClient({
        chain: anvil,
        transport: http(execRpcUrl),
    });
    const bundlerClient = new BundlerClient(anvil, http(bundlerRpcUrl), ENTRY_POINT);
    const walletClient = createWalletClient({
        chain: anvil,
        transport: http(execRpcUrl),
    });
    const account = privateKeyToAccount(PRIVATE_KEY);

    // Shield tc commitment
    const denomination = await publicClient.readContract({
        address: TORNADO_INSTANCE_ADDR,
        abi: tornadoAbi,
        functionName: "denomination",
    });
    const hash = await walletClient.writeContract({
        account,
        address: TORNADO_INSTANCE_ADDR,
        abi: tornadoAbi,
        functionName: "deposit",
        args: [COMMITMENT],
        value: denomination,
    });
    console.log("Deposit tx:", hash);

    // Unshield via bundler
    const op = await new TornadoBuilder(TORNADO_ACCOUNT)
        .withPaymaster(PAYMASTER)
        .withWithdraw(PROOF_VALID, ROOT, NULLIFIER_HASH, RECIPIENT, PAYMASTER, FEE)
        .withGas({
            type: 'manual',
            callGasLimit: 1_500_000n,
            verificationGasLimit: 500_000n,
            preVerificationGas: 100_000n,
            maxFeePerGas: 1000000000n,
            maxPriorityFeePerGas: 1000000000n * 10n,
            paymasterVerificationGasLimit: 300_000n,
            paymasterPostOpGasLimit: 100_000n,
        }).build(publicClient, bundlerClient);
    const userOpHash = await bundlerClient.sendUserOperation(op);

    console.log("Waiting for user operation receipt...");
    await bundlerClient.waitForUserOperationReceipt(userOpHash);

    const [recipientBalance, paymasterBalance] = await Promise.all([
        publicClient.getBalance({ address: RECIPIENT }),
        publicClient.getBalance({ address: PAYMASTER }),
    ]);

    const expectedRecipient = denomination - FEE;
    console.assert(recipientBalance === expectedRecipient, `Recipient balance wrong: expected ${expectedRecipient}, got ${recipientBalance}`);
    console.assert(paymasterBalance === FEE, `Paymaster balance wrong: expected ${FEE}, got ${paymasterBalance}`);
    console.log("Balances OK: recipient", recipientBalance, "paymaster", paymasterBalance);
} finally {
    await stop();
}

async function startServers(rpcUrl: string): Promise<{
    execRpcUrl: string;
    bundlerRpcUrl: string;
    stop: () => Promise<void>;
}> {
    const execServer = Instance.anvil({
        forkUrl: rpcUrl,
        forkBlockNumber: 10_000_000,
        chainId: anvil.id,
        loadState: "../anvil-state.json",
    });
    // execServer.on("stdout", (data) => {
    //     console.log(`[Anvil] ${data}`);
    // });
    // execServer.on("stderr", (data) => {
    //     console.error(`[Anvil] ${data}`);
    // });
    await execServer.start();
    const executionRpcUrl = `http://localhost:${execServer.port}`;

    const bundlerServer = Instance.alto({
        rpcUrl: executionRpcUrl,
        entrypoints: [entryPoint09Address],
        executorPrivateKeys: [EXECUTOR_PK],
        utilityPrivateKey: UTILITY_PK,
        safeMode: false,
    });
    // bundlerServer.on("stdout", (data) => {
    //     console.log(`[Alto] ${data}`);
    // });
    // bundlerServer.on("stderr", (data) => {
    //     console.error(`[Alto] ${data}`);
    // });
    await bundlerServer.start();
    const bundlerRpcUrl = `http://localhost:${bundlerServer.port}`;

    console.log("Execution RPC URL:", executionRpcUrl);
    console.log("Bundler RPC URL:", bundlerRpcUrl);

    return {
        execRpcUrl: executionRpcUrl,
        bundlerRpcUrl: bundlerRpcUrl,
        stop: async () => {
            await execServer.stop();
            await bundlerServer.stop();
        },
    };
}
