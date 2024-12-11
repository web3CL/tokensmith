import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import dotenv from 'dotenv';
import { z } from 'zod';

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


    // input the package id
    const packageObjectId = '0x0ba87d5477f2ff33f9c51b479329a73736e0f1eb847db96ab902a80ef09ae9eb';
    // mock coin
    const treasryCap = '0x353cd8638d91ce0f2169c13ba8d1334d6b72a8927681261caba2268fd8a916f0';
    const amount = BigInt(100_000_000);
    const gas_amount = BigInt(10000000);
    
    

    const tx = new Transaction();
    tx.setGasBudget(gas_amount);

    tx.moveCall({
        target: `${packageObjectId}::mock_usdc::mint`,
        arguments: [tx.object(treasryCap), tx.pure.u64(amount)],
    });

    try {
        console.log('Attempting to sign and execute transaction...');
        const result = await client.signAndExecuteTransaction({
            signer: keypair,
            transaction: tx,
        });    
        console.log(result);
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
                console.error('One or more referenced objects not found. Check your packageObjectId and treasryCap.');
            }
        } else {
            console.error('Unknown error occurred:', error);
        }
        throw error; // Re-throw the error for upstream handling
    }
}

// Add error handling for the main function as well
main().catch(error => {
    console.error('Program failed:', error);
    process.exit(1);
});