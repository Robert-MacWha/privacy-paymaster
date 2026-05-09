import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { Instance } from "prool";
import { createWalletClient, getContract, http, parseAbi, publicActions, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { anvil } from "viem/chains";
import { BundlerClient } from "../src/bundlerClient";
import { TornadoBuilder } from "../src/tornadoBuilder";
import { runForge, setPkBalances } from "./utils";
import chain from "../../config/chains/sepolia.toml";
import configFixtures from "../../test/fixtures/tornadocash/config.json";
import shieldFixtures from "../../test/fixtures/tornadocash/shield.json";
import unshieldFixtures from "../../test/fixtures/tornadocash/unshield.json";

const tornadoAbi = parseAbi([
    "function deposit(bytes32 _commitment) external payable",
    "function denomination() external view returns(uint256)",
]);

const SEPOLIA_RPC_URL: string | undefined = process.env.SEPOLIA_RPC_URL;
if (!SEPOLIA_RPC_URL)
    throw new Error("SEPOLIA_RPC_URL env must be defined");

const FORK_BLOCK_NUMBER = configFixtures.forkBlockNumber;
const DEPLOYER_PK = configFixtures.deployerPrivateKey as Hex;
const ALTO_EXECUTOR_PK = "0x4a3a02862ddcb260ed52d40ef03f8e3d78fa3d174b0ef333afdf1ffb4a648cd5" as Hex;
const ALTO_UTILITY_PK = "0xdd4b2564c83ff7de602c39ffda1146055dc1814b07c083d7971722384f1f01a6" as Hex;

// Test fixtures
const STAKE_AMOUNT = "100000000000000000";
const UNSTAKE_DELAY = "3600";
const DEPOSIT_AMOUNT = "100000000000000000";

// Assigned in `beforeAll`
let execRpcUrl: string;
let bundlerClient: BundlerClient;
let stop: () => Promise<void>;
let client: ReturnType<typeof createWalletClient> & ReturnType<typeof publicActions>;

let paymasterAddr: Address = "0x00";
let tornadoAccountAddr: Address = "0x00";

beforeAll(async () => {
    const servers = await startServers(SEPOLIA_RPC_URL);
    stop = servers.stop;
    execRpcUrl = servers.execRpcUrl;

    await setupTornadocash(execRpcUrl);

    bundlerClient = new BundlerClient(servers.bundlerRpcUrl, chain.protocols.erc4337.entry_point);
    client = createWalletClient({
        chain: anvil,
        transport: http(execRpcUrl),
    }).extend(publicActions);

}, 60_000);

afterAll(async () => {
    await stop();
});

describe("tornado paymaster e2e", () => {
    test("deposit and withdraw via bundler yields correct balances", async () => {
        const account = privateKeyToAccount(DEPLOYER_PK);  // 
        const Tornado = getContract({
            address: chain.protocols.tornado.eth_1.instance,
            abi: tornadoAbi,
            client
        });

        // Shield tc commitment
        const denomination = await Tornado.read.denomination();

        console.log("Depositing to TC...")
        const hash = await Tornado.write.deposit([shieldFixtures.commitment as Hex], {
            chain: anvil,
            account,
            value: denomination,
        });
        console.log("Deposit tx:", hash);

        const authorization = await client.signAuthorization({
            account,
            contractAddress: tornadoAccountAddr,
        });

        // Unshield via bundler
        console.log("Unshielding via bundler...");
        const op = await new TornadoBuilder(account.address)
            .withPaymaster(paymasterAddr)
            .withWithdraw(unshieldFixtures.proof as Hex, unshieldFixtures.root as Hex, unshieldFixtures.nullifierHash as Hex, unshieldFixtures.recipient as Address, unshieldFixtures.relayer as Address, BigInt(unshieldFixtures.fee as number))
            .withAuthorization(authorization)
            .withGas({
                type: 'manual',
                callGasLimit: 1_500_000n,
                verificationGasLimit: 500_000n,
                preVerificationGas: 100_000n,
                maxFeePerGas: 1000000000n,
                maxPriorityFeePerGas: 1000000000n * 10n,
                paymasterVerificationGasLimit: 500_000n,
                paymasterPostOpGasLimit: 100_000n,
            })
            .build(client, bundlerClient);
        const userOpHash = await bundlerClient.sendUserOperation(op);

        console.log("Waiting for user operation receipt...");
        await bundlerClient.waitForUserOperationReceipt(userOpHash);

        const [recipientBalance, paymasterBalance] = await Promise.all([
            client.getBalance({ address: unshieldFixtures.recipient as Address }),
            client.getBalance({ address: paymasterAddr }),
        ]);

        const expectedRecipient = denomination - BigInt(unshieldFixtures.fee as number);
        expect(recipientBalance).toBe(expectedRecipient);
        expect(paymasterBalance).toBe(BigInt(unshieldFixtures.fee as number));
    }, 120_000);
});

async function startServers(rpcUrl: string): Promise<{
    execRpcUrl: string;
    bundlerRpcUrl: string;
    stop: () => Promise<void>;
}> {
    const execServer = Instance.anvil({
        forkUrl: rpcUrl,
        forkBlockNumber: FORK_BLOCK_NUMBER,
        chainId: anvil.id,
    });
    await execServer.start();
    const executionRpcUrl = `http://localhost:${execServer.port}`;

    await setPkBalances(executionRpcUrl, [DEPLOYER_PK, ALTO_EXECUTOR_PK, ALTO_UTILITY_PK]);

    const bundlerServer = Instance.alto({
        rpcUrl: executionRpcUrl,
        entrypoints: [chain.protocols.erc4337.entry_point],
        executorPrivateKeys: [ALTO_EXECUTOR_PK],
        utilityPrivateKey: ALTO_UTILITY_PK,
        safeMode: false,
    });
    await bundlerServer.start();
    const bundlerRpcUrl = `http://localhost:${bundlerServer.port}`;

    return {
        execRpcUrl: executionRpcUrl,
        bundlerRpcUrl,
        stop: async () => {
            await execServer.stop();
            await bundlerServer.stop();
        },
    };
}

async function setupTornadocash(forkUrl: string) {
    console.log("Deploying Paymaster");
    const deploymentsPath = "../config/deployments/anvil-test.json";

    // Clear previous deployments
    await Bun.write(deploymentsPath, "{}");

    // Deploy
    const env = { ...process.env, DEPLOY_ENV: "anvil-test", PRIVATE_KEY: DEPLOYER_PK };
    await runForge(["script", "DeployPaymaster", "--fork-url", forkUrl, "--broadcast"], env);
    await runForge(["script", "StakePaymaster", "--fork-url", forkUrl, "--broadcast"], { ...env, STAKE_AMOUNT, UNSTAKE_DELAY, DEPOSIT_AMOUNT });
    await runForge(["script", "DeployTornado", "--fork-url", forkUrl, "--broadcast"], env);

    // Load deployed addrs
    const deployments = await Bun.file(deploymentsPath).json();
    paymasterAddr = deployments.paymaster.address as Address;
    tornadoAccountAddr = deployments.tornado.tornadoAccount as Address;
}

