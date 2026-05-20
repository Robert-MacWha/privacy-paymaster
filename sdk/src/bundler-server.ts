import { Instance } from "prool";
import { createTestClient, http, parseEther } from "viem";
import { privateKeyToAddress } from "viem/accounts";
import { anvil } from "viem/chains";
import type { Address, Hex } from "viem";

const DEFAULT_EXECUTOR_PK = "0x4a3a02862ddcb260ed52d40ef03f8e3d78fa3d174b0ef333afdf1ffb4a648cd5" as Hex;
const DEFAULT_UTILITY_PK  = "0xdd4b2564c83ff7de602c39ffda1146055dc1814b07c083d7971722384f1f01a6" as Hex;

export interface StartServersOptions {
    // Provide execRpcUrl to connect to an existing node, or forkUrl to spin up a local anvil fork.
    execRpcUrl?: string;
    forkUrl?: string;
    forkBlockNumber?: bigint | number;
    entrypoint: Address;
    executorPrivateKey?: Hex;
    utilityPrivateKey?: Hex;
    port?: number;
    // Only applies in fork mode — anvil_setBalance is unavailable on external nodes.
    fundedPrivateKeys?: Hex[];
    safeMode?: boolean;
}

export interface ServersResult {
    execRpcUrl: string;
    bundlerRpcUrl: string;
    stop: () => Promise<void>;
}

export async function startServers(options: StartServersOptions): Promise<ServersResult> {
    const {
        forkUrl,
        forkBlockNumber,
        entrypoint,
        executorPrivateKey = DEFAULT_EXECUTOR_PK,
        utilityPrivateKey = DEFAULT_UTILITY_PK,
        fundedPrivateKeys = [],
        safeMode = false,
        port = 8545
    } = options;

    if (!options.execRpcUrl && !forkUrl)
        throw new Error("Either execRpcUrl or forkUrl must be provided");

    let execRpcUrl: string;
    let stopExec: (() => Promise<void>) | undefined;

    if (options.execRpcUrl) {
        execRpcUrl = options.execRpcUrl;
    } else {
        const execServer = Instance.anvil({
            forkUrl: forkUrl!,
            forkBlockNumber,
            chainId: anvil.id,
            port,
        });
        await execServer.start();
        execRpcUrl = `http://localhost:${execServer.port}`;
        stopExec = () => execServer.stop();

        const allPks = [executorPrivateKey, utilityPrivateKey, ...fundedPrivateKeys];
        const testClient = createTestClient({ chain: anvil, mode: "anvil", transport: http(execRpcUrl) });
        for (const pk of allPks) {
            await testClient.setBalance({ address: privateKeyToAddress(pk), value: parseEther("1000") });
        }
    }

    const bundlerServer = Instance.alto({
        rpcUrl: execRpcUrl,
        entrypoints: [entrypoint],
        executorPrivateKeys: [executorPrivateKey],
        utilityPrivateKey,
        safeMode,
    });
    await bundlerServer.start();
    const bundlerRpcUrl = `http://127.0.0.1:${bundlerServer.port}`;

    return {
        execRpcUrl,
        bundlerRpcUrl,
        stop: async () => {
            await stopExec?.();
            await bundlerServer.stop();
        },
    };
}
