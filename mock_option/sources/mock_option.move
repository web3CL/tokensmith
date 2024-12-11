/// Module: mock_asset_coin
module mock_option::mock_option;

use sui::coin::{Self};
use sui::url;

// the option coin should have the same decimal as the underlying assets!
const DECIMALS: u8 = 8;
const SYMBOL: vector<u8> = b"MOPTION";
const NAME: vector<u8> = b"MOCK OPTION COIN";
const DESCRIPTION: vector<u8> = b"This is a testcoin for tokensmith";
const ICON_URL: vector<u8> = b"https://e7.pngegg.com/pngimages/528/930/png-clipart-trader-futures-contract-investing-online-market-exchange-others-investment-logo.png";

// OTW
public struct MOCK_OPTION has drop {}

fun init(otw: MOCK_OPTION, ctx: &mut TxContext) {
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

    transfer::public_transfer(tcap, ctx.sender());
    transfer::public_transfer(metadata, ctx.sender());
}


