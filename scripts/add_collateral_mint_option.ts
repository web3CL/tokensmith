import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import dotenv from 'dotenv';
import { z } from 'zod';

// Constants
const CALL_OPTION = 0;
const PUT_OPTION = 1;
const CLOCK_ADDRESS = '0x6';

async function main() {
    dotenv.config();

    const pk = String(process.env.privatekey);
    const keypair = Ed25519Keypair.fromSecretKey(pk);

    const client = new SuiClient({
        url: getFullnodeUrl('testnet'),
    });

    try {
        console.log('Current Address:', keypair.getPublicKey().toSuiAddress())
        const balance = await client.getBalance({
            owner: keypair.getPublicKey().toSuiAddress(),
            coinType: '0x2::sui::SUI'
        });
        console.log('Current balance:', balance);
        
        if (BigInt(balance.totalBalance) === BigInt(0)) {
            throw new Error('Wallet has no SUI tokens. Please get some from the faucet first.');
        }
    } catch (error) {
        console.error('Error checking balance:', error);
        throw error;
    }

    // Contract configuration
    const packageObjectId = '0xd82198a8369825beb19a2c4c5209bbe33b1b6dcd320c1b2e7145a54ced05f8b6';
    const marketplaceObjectId = '0x6231761053767f8680abc0ae9570483d9aae0fb19f6388c9749dd9574d6afa54';
    const gas_amount = BigInt(10000000);

    // You'll need to get these from your wallet or previous transactions
    const vaultOwnerId = '0xe34b00924a15146dc156d5160f03f387ff927b1c2e1bd945e20d566acbdacdaa';
    const assetCoinId = '0x44c2eafa033c9c08f684fb0578b5175aec231b99933b3a324f70db300fc65130';

    const tx = new Transaction();
    tx.setGasBudget(gas_amount);

    // Call write_covered_call function
    tx.moveCall({
        target: `${packageObjectId}::tokensmith::write_covered_call`,
        arguments: [
            tx.object(marketplaceObjectId), // marketplace
            tx.object(vaultOwnerId), // vault_owner
            tx.object(CLOCK_ADDRESS), // clock
            tx.object(assetCoinId), // asset coin
        ],
        typeArguments: [
            '0x0ba87d5477f2ff33f9c51b479329a73736e0f1eb847db96ab902a80ef09ae9eb::mock_coin::MOCK_COIN',
            '0x0ba87d5477f2ff33f9c51b479329a73736e0f1eb847db96ab902a80ef09ae9eb::mock_usdc::MOCK_USDC',
            '0x1324676a00603e868b87d29997926e2bc5015889a986dc857ee84543a1cd0ead::mock_option::MOCK_OPTION'
        ]
    });

    try {
        console.log('Attempting to write covered call option...');
        const result = await client.signAndExecuteTransaction({
            signer: keypair,
            transaction: tx,
        });    
        console.log('Transaction result:', result);
        return result;
        
    } catch (error) {
        if (error instanceof Error) {
            console.error('Transaction failed with error:', {
                name: error.name,
                message: error.message,
                stack: error.stack
            });

            // Enhanced error handling for write_covered_call specific errors
            if (error.message.includes('EOptionType')) {
                console.error('Invalid option type. Must be a CALL option.');
            } else if (error.message.includes('insufficient gas')) {
                console.error('Transaction failed due to insufficient gas. Try increasing gas_amount.');
            } else if (error.message.includes('authority signature')) {
                console.error('Transaction failed due to invalid signature. Check your keypair.');
            } else if (error.message.includes('object not found')) {
                console.error('One or more objects not found. Check your marketplaceObjectId, vaultOwnerId, and assetCoinId.');
            } else if (error.message.includes('type mismatch')) {
                console.error('Type arguments mismatch. Check your asset, USDC, and option coin types.');
            }
        } else {
            console.error('Unknown error occurred:', error);
        }
        throw error;
    }
}

// Add error handling for the main function
main().catch(error => {
    console.error('Program failed:', error);
    process.exit(1);
});