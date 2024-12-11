import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import dotenv from 'dotenv';
import { z } from 'zod';

// Constants
const CALL_OPTION = 0;
const PUT_OPTION = 1;

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
    const packageObjectId = '0xd82198a8369825beb19a2c4c5209bbe33b1b6dcd320c1b2e7145a54ced05f8b6'; // Replace with your package ID
    const treasuryCap = '0xb7a34897a47a39cb8576efcd504fa129300c9a78ca1d83b2903bb19adf2757bf'; // Replace with your treasury cap
    const marketplaceObjectId = '0x6231761053767f8680abc0ae9570483d9aae0fb19f6388c9749dd9574d6afa54'; // Replace with your marketplace object ID
    const gas_amount = BigInt(10000000);

    // Option vault parameters
    const optionType = CALL_OPTION;
    const expireDate = BigInt(Date.now() + 3600000); // 1 hour from now
    const priceNumerator = BigInt(100);
    const priceDenominator = BigInt(1);
    const assetDecimals = 8;
    const usdcDecimals = 6;



    const tx = new Transaction();
    tx.setGasBudget(gas_amount);


    // Initialize option vault
    tx.moveCall({
        target: `${packageObjectId}::tokensmith::init_option_vault`,
        arguments: [
            tx.object('0x6'), // Clock object ID
            tx.object(treasuryCap),
            tx.pure.u8(optionType),
            tx.pure.u64(expireDate),
            tx.pure.u64(priceNumerator),
            tx.pure.u64(priceDenominator),
            tx.pure.u8(assetDecimals),
            tx.pure.u8(usdcDecimals),
            tx.object(marketplaceObjectId)
        ],
        typeArguments: [
            '0x0ba87d5477f2ff33f9c51b479329a73736e0f1eb847db96ab902a80ef09ae9eb::mock_coin::MOCK_COIN', // Replace with your asset type
            '0x0ba87d5477f2ff33f9c51b479329a73736e0f1eb847db96ab902a80ef09ae9eb::mock_usdc::MOCK_USDC',  // Replace with your USDC type
            '0x1324676a00603e868b87d29997926e2bc5015889a986dc857ee84543a1cd0ead::mock_option::MOCK_OPTION' // Replace with your option coin type
        ]
    });

    try {
        console.log('Attempting to sign and execute transaction...');
        const result = await client.signAndExecuteTransaction({
            signer: keypair,
            transaction: tx,
        });    
        console.log('Transaction result:', result);
        return result;
        
    } catch (error) {
        // Handle specific error types
        if (error instanceof Error) {
            console.error('Transaction failed with error:', {
                name: error.name,
                message: error.message,
                stack: error.stack
            });

            // Check for specific error conditions
            if (error.message.includes('insufficient gas')) {
                console.error('Transaction failed due to insufficient gas. Try increasing gas_amount.');
            } else if (error.message.includes('authority signature')) {
                console.error('Transaction failed due to invalid signature. Check your keypair.');
            } else if (error.message.includes('object not found')) {
                console.error('One or more referenced objects not found. Check your packageObjectId and treasuryCap.');
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