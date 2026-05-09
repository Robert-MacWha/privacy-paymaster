import { createTestClient, http, parseEther, type Address, type Hex } from "viem";
import { privateKeyToAddress } from "viem/accounts";
import { anvil } from "viem/chains";

// Runs a forge command with the given args and environment variables
export async function runForge(args: string[], env: Record<string, string>) {
    console.log(`Running: forge ${args.join(" ")}`);

    const proc = Bun.spawn(["forge", ...args], { env, stdout: "pipe", stderr: "pipe" });
    const code = await proc.exited;
    if (code !== 0) {
        const stderr = await new Response(proc.stderr).text();
        throw new Error(`forge ${args.join(" ")} failed: ${stderr}`);
    }
}

// Sets balances for given addresses on the forked chain
export async function setBalances(forkUrl: string, addresses: Address[], value: bigint = parseEther("1000")) {
    console.log("Funding addresses");
    const testClient = createTestClient({ chain: anvil, mode: "anvil", transport: http(forkUrl) });

    for (const addr of addresses) {
        console.log(`Funding ${addr}`);
        await testClient.setBalance({
            address: addr,
            value: value
        });
    }
}

export async function setPkBalances(forkUrl: string, privateKeys: Hex[], value: bigint = parseEther("1000")) {
    const addresses = privateKeys.map(privateKeyToAddress);
    await setBalances(forkUrl, addresses, value);
}