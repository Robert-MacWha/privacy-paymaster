import { createClient, http, publicActions, walletActions } from 'viem'
import { arbitrumSepolia } from 'viem/chains'
import { privateKeyToAccount } from 'viem/accounts'
import { toSimple7702SmartAccount } from 'viem/account-abstraction'

export const owner = privateKeyToAccount('0x...');

export const client = createClient({
    account: owner,
    chain: arbitrumSepolia,
    transport: http()
})
    .extend(publicActions)
    .extend(walletActions);

export const account = await toSimple7702SmartAccount({ client, owner });

export const paymasterAddress = '0x3BA9A96eE3eFf3A69E2B18886AcF52027EFF8966';
export const usdcAddress = '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d'; 