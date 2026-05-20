import { startServers } from "../src/bundler-server.js";
import type { Address, Hex } from "viem";

const execRpcUrl = process.env.EXEC_RPC_URL;
const forkUrl = process.env.FORK_RPC_URL;

if (!execRpcUrl && !forkUrl)
    throw new Error("Either EXEC_RPC_URL or FORK_RPC_URL env must be defined");

const entrypoint = process.env.ENTRYPOINT;
if (!entrypoint) throw new Error("ENTRYPOINT env must be defined");

const forkBlockNumber = process.env.FORK_BLOCK_NUMBER
    ? BigInt(process.env.FORK_BLOCK_NUMBER)
    : undefined;

const fundedPrivateKeys = process.env.FUND_PKS
    ? (process.env.FUND_PKS.split(",").map((pk) => pk.trim()) as Hex[])
    : [];

const servers = await startServers({
    execRpcUrl,
    forkUrl,
    forkBlockNumber,
    entrypoint: entrypoint as Address,
    executorPrivateKey: process.env.ALTO_EXECUTOR_PK as Hex | undefined,
    utilityPrivateKey: process.env.ALTO_UTILITY_PK as Hex | undefined,
    fundedPrivateKeys,
});

console.log(`Execution RPC: ${servers.execRpcUrl}`);
console.log(`Bundler RPC:   ${servers.bundlerRpcUrl}`);

const shutdown = async () => {
    await servers.stop();
    process.exit(0);
};

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

await new Promise(() => {});
