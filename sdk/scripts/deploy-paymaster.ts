import { deployPaymaster } from "../src/deploy-paymaster.js";
import type { Hex } from "viem";

const forkUrl = process.env.FORK_RPC_URL;
if (!forkUrl) throw new Error("FORK_RPC_URL env must be defined");

const privateKey = process.env.PRIVATE_KEY;
if (!privateKey) throw new Error("PRIVATE_KEY env must be defined");

const result = await deployPaymaster({
    forkUrl,
    privateKey: privateKey as Hex,
    deployEnv: process.env.DEPLOY_ENV,
    stakeAmount: process.env.STAKE_AMOUNT,
    unstakeDelay: process.env.UNSTAKE_DELAY,
    depositAmount: process.env.DEPOSIT_AMOUNT,
});

console.log(`Paymaster:      ${result.paymasterAddress}`);
console.log(`TornadoAccount: ${result.tornadoAccountAddress}`);
