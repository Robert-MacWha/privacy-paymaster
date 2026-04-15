import initWasm, { BundlerProvider, UserOperationBuilder } from './pkg/index';

let initPromise: Promise<any> | null = null;

async function init() {
    if (!initPromise) {
        initPromise = initWasm();
    }
    await initPromise;
}

export async function createBundlerProvider(rpc_url: string, bundler_url: string, entry_point: `0x${string}`): Promise<BundlerProvider> {
    await init();
    return BundlerProvider.new(rpc_url, bundler_url, entry_point);
}
