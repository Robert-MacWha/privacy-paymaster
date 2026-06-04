import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Hex } from "viem";

export interface DeployPaymasterOptions {
    forkUrl: string;
    privateKey: Hex;
    deployEnv?: string;
    stakeAmount?: string;
    unstakeDelay?: string;
    depositAmount?: string;
}

export interface DeploymentResult {
    paymasterAddress: `0x${string}`;
    tornadoAdapterAddress: `0x${string}`;
}

function findProjectRoot(startDir: string): string {
    let dir = startDir;
    while (true) {
        if (existsSync(join(dir, "foundry.toml"))) return dir;
        const parent = dirname(dir);
        if (parent === dir) throw new Error("Could not find foundry.toml — run from inside the privacy-paymaster project");
        dir = parent;
    }
}

function forge(args: string[], env: NodeJS.ProcessEnv, cwd: string): Promise<void> {
    return new Promise((resolve, reject) => {
        console.log(`Running: forge ${args.join(" ")}`);
        const proc = spawn("forge", args, { env, cwd, stdio: ["ignore", "ignore", "pipe"] });
        let stderr = "";
        proc.stderr!.on("data", (chunk: Buffer) => { stderr += chunk.toString(); });
        proc.on("close", (code) => {
            if (code !== 0) reject(new Error(`forge ${args.join(" ")} failed:\n${stderr}`));
            else resolve();
        });
    });
}

export async function deployPaymaster(options: DeployPaymasterOptions): Promise<DeploymentResult> {
    const {
        forkUrl,
        privateKey,
        deployEnv = "anvil-test",
        stakeAmount = "100000000000000000",
        unstakeDelay = "3600",
        depositAmount = "100000000000000000",
    } = options;

    const projectRoot = findProjectRoot(dirname(fileURLToPath(import.meta.url)));
    const deploymentsPath = join(projectRoot, `config/deployments/${deployEnv}.json`);

    await writeFile(deploymentsPath, "{}");

    const env: NodeJS.ProcessEnv = { ...process.env, DEPLOY_ENV: deployEnv, PRIVATE_KEY: privateKey };
    await forge(["script", "DeployPaymaster", "--fork-url", forkUrl, "--broadcast"], env, projectRoot);
    await forge(["script", "StakePaymaster", "--fork-url", forkUrl, "--broadcast"], {
        ...env, STAKE_AMOUNT: stakeAmount, UNSTAKE_DELAY: unstakeDelay, DEPOSIT_AMOUNT: depositAmount,
    }, projectRoot);
    await forge(["script", "DeployTornado", "--fork-url", forkUrl, "--broadcast"], env, projectRoot);

    const deployments = JSON.parse(await readFile(deploymentsPath, "utf-8"));
    return {
        paymasterAddress: deployments.paymaster.address as `0x${string}`,
        tornadoAdapterAddress: deployments.tornado_eth_1.tornadoAdapter as `0x${string}`,
    };
}
