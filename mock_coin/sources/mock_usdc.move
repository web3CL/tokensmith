
module mock_coin::mock_usdc;

use sui::coin::{Self, TreasuryCap};
use sui::url;

const DECIMALS: u8 = 6;
const SYMBOL: vector<u8> = b"MUSDC";
const NAME: vector<u8> = b"MOCK USDC";
const DESCRIPTION: vector<u8> = b"This is a testcoin for tokensmith";
const ICON_URL: vector<u8> = b"https://cdn.prod.website-files.com/66327d2c71b7019a2a9a1b62/667454fd94c7f58e94f4a009_USDC-webclip-256x256.png";

// OTW
public struct MOCK_USDC has drop {}

fun init(otw: MOCK_USDC, ctx: &mut TxContext) {
    let icon_url = url::new_unsafe_from_bytes(ICON_URL);
    let (tcap, metadata) = coin::create_currency(
        otw,
        DECIMALS,
        SYMBOL,
        NAME,
        DESCRIPTION,
        option::some(icon_url),
        ctx,
    );

    transfer::public_share_object(tcap);
    transfer::public_transfer(metadata, ctx.sender());
}

public entry fun mint(tcap: &mut TreasuryCap<MOCK_USDC>, num: u64, ctx: &mut TxContext){
    transfer::public_transfer(coin::mint(tcap, num, ctx), ctx.sender());
}

