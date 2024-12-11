/// Module: mock_asset_coin
module mock_coin::mock_coin;

use sui::coin::{Self, TreasuryCap};
use sui::url;

const DECIMALS: u8 = 8;
const SYMBOL: vector<u8> = b"MBTC";
const NAME: vector<u8> = b"MOCK BTC";
const DESCRIPTION: vector<u8> = b"This is a testcoin for tokensmith";
const ICON_URL: vector<u8> = b"https://upload.wikimedia.org/wikipedia/commons/thumb/4/46/Bitcoin.svg/1200px-Bitcoin.svg.png";

// OTW
public struct MOCK_COIN has drop {}

fun init(otw: MOCK_COIN, ctx: &mut TxContext) {
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

public entry fun mint(tcap: &mut TreasuryCap<MOCK_COIN>, num: u64, ctx: &mut TxContext){
    transfer::public_transfer(coin::mint(tcap, num, ctx), ctx.sender());
}

