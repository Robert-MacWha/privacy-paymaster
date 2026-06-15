import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { createClient, getContract, http, parseAbi, publicActions, walletActions, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { anvil } from "viem/chains";
import { startServers } from "../src/bundler-server";
import { deployPaymaster } from "../src/deploy-paymaster";
import chain from "../../config/chains/sepolia.toml";
import configFixtures from "../../test/fixtures/tornadocash/config.json";
import shieldFixtures from "../../test/fixtures/tornadocash/shield.json";
import unshieldFixtures from "../../test/fixtures/tornadocash/unshield.json";
import { createBundlerClient, toSimple7702SmartAccount } from "viem/account-abstraction";
import { encodePaymasterData, encodeTornadoAdapterData } from "../src/adapter-data";

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

// Assigned in `beforeAll`
let execRpcUrl: string;
let bundlerRpcUrl: string;
let stop: () => Promise<void>;

let paymasterAddr: Address = "0x00";
let tornadoAdapterAddr: Address = "0x00";

beforeAll(async () => {
    const servers = await startServers({
        forkUrl: SEPOLIA_RPC_URL,
        forkBlockNumber: FORK_BLOCK_NUMBER,
        entrypoint: chain.protocols.erc4337.entry_point,
        executorPrivateKey: ALTO_EXECUTOR_PK,
        utilityPrivateKey: ALTO_UTILITY_PK,
        fundedPrivateKeys: [DEPLOYER_PK],
    });
    stop = servers.stop;
    execRpcUrl = servers.execRpcUrl;
    bundlerRpcUrl = servers.bundlerRpcUrl;

    await setupTornadocash(execRpcUrl);
}, 60_000);

afterAll(async () => {
    await stop();
});

describe("tornado paymaster e2e", () => {
    test("deposit and withdraw via bundler yields correct balances", async () => {
        const client = createClient({
            chain: anvil,
            transport: http(execRpcUrl),
        }).extend(publicActions).extend(walletActions);
        const bundlerClient = createBundlerClient({
            client,
            transport: http(bundlerRpcUrl),
        });
        const owner = privateKeyToAccount(DEPLOYER_PK);
        const account = await toSimple7702SmartAccount({ client, owner });


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
            account: owner,
            value: denomination,
        });
        console.log("Deposit tx:", hash);

        // Unshield via bundler
        console.log("Unshielding via bundler...");

        const paymasterData = encodePaymasterData(
            tornadoAdapterAddr,
            encodeTornadoAdapterData(
                unshieldFixtures.proof as Hex,
                unshieldFixtures.root as Hex,
                unshieldFixtures.nullifierHash as Hex,
                unshieldFixtures.recipient as Address,
                unshieldFixtures.relayer as Address,
                BigInt(unshieldFixtures.fee as number),
                BigInt(0)
            )
        );

        const authorization = await client.signAuthorization(account.authorization);
        //? Using fixed gas limits so they match against the fixture's expected values.
        const userOpHash = await bundlerClient.sendUserOperation({
            account,
            authorization,
            calls: [],
            paymaster: paymasterAddr,
            paymasterData,
            callGasLimit: 0n,
            verificationGasLimit: 500_000n,
            preVerificationGas: 100_000n,
            maxFeePerGas: 1000000000n,
            maxPriorityFeePerGas: 1000000000n * 10n,
            paymasterVerificationGasLimit: 500_000n,
            paymasterPostOpGasLimit: 100_000n,
        });

        console.log("Waiting for user operation receipt...");
        await bundlerClient.waitForUserOperationReceipt({ hash: userOpHash });

        const [recipientBalance, paymasterBalance] = await Promise.all([
            client.getBalance({ address: unshieldFixtures.recipient as Address }),
            client.getBalance({ address: paymasterAddr }),
        ]);

        expect(paymasterBalance).toBe(502307000000000n);
        expect(recipientBalance).toBe(999497693000000000n);
    }, 120_000);
});

async function setupTornadocash(forkUrl: string) {
    console.log("Deploying Paymaster");
    const { paymasterAddress, tornadoAdapterAddress } = await deployPaymaster({
        forkUrl,
        privateKey: DEPLOYER_PK,
    });
    paymasterAddr = paymasterAddress;
    tornadoAdapterAddr = tornadoAdapterAddress;
}
