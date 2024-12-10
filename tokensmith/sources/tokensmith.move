/*
    Warning!
    1) the decimal of option coin should be the same as underlying assets
*/

module tokensmith::tokensmith;

    use std::type_name::{Self, TypeName};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance};
    use sui::dynamic_object_field as dof;
    use sui::clock::{Clock, Self};
    use std::u64::pow;

    // Error codes
    const EOwnerError: u64 = 1;
    const EExpired: u64 = 2;
    const ETimeIllegal: u64 = 3;
    const EOption: u64 = 4;
    const EPriceInvalid: u64 = 5;
    const EWithdrawTooEarly: u64 = 6;
    const EInsufficientCollateral: u64 = 7;
    const EOptionType: u64 = 8;

    // Time constants (in milliseconds)
    const MILLISECONDS_PER_DAY: u64 = 86400000; // 24 * 60 * 60 * 1000
    const WITHDRAWAL_DELAY: u64 = 7 * MILLISECONDS_PER_DAY;

    // Option types
    const CALL_OPTION: u8 = 0;
    const PUT_OPTION: u8 = 1;

    /// Represents the exercise price as a fraction
    public struct ExercisePrice has store, copy, drop {
        numerator: u64,
        denominator: u64
    }

    /// Unified vault for both covered call and put options
    public struct OptionVault<phantom Asset, phantom USDC, phantom OPTION_COIN> has key, store {
    id: UID,
    option_type: u8,                       // 0 for call, 1 for put
    asset_balance: Balance<Asset>,         // For calls: locked assets, For puts: received assets
    usdc_balance: Balance<USDC>,          // For calls: exercise pool, For puts: collateral
    exercise_price: ExercisePrice,         // Price in USDC per unit of asset
    expire_date: u64,                      // Expiration timestamp
    owner: address,                        // Vault owner address
    treasury_cap: TreasuryCap<OPTION_COIN>, // For minting option tokens
    asset_decimals: u8,                    // Decimals of the underlying asset
    usdc_decimals: u8                     // Decimals of USDC
    }

    public struct Marketplace has key {
        id: UID,
    }

    public struct VaultOwner has key {
        id: UID,
        option_coin_type: TypeName,
        marketplace: address
    }

    fun init(ctx: &mut TxContext) {
        let marketplace = Marketplace { id: object::new(ctx) };
        transfer::share_object(marketplace);
    }

    /// Create new option vault (either call or put)
    public fun init_option_vault<Asset, USDC, OPTION_COIN>(
        clock: &Clock,
        treasury_cap: TreasuryCap<OPTION_COIN>,
        option_type: u8,
        expire_date: u64,
        price_numerator: u64,
        price_denominator: u64,
        asset_decimals: u8,
        usdc_decimals: u8,
        marketplace: &mut Marketplace,
        ctx: &mut TxContext
    ) {
        let typename = type_name::get<OPTION_COIN>();
        
        // Validate inputs
        assert!(option_type == CALL_OPTION || option_type == PUT_OPTION, EOptionType);
        assert!(clock::timestamp_ms(clock) < expire_date, ETimeIllegal);
        assert!(coin::total_supply(&treasury_cap) == 0, EOption);
        assert!(price_denominator > 0, EPriceInvalid);

        let exercise_price = ExercisePrice {
            numerator: price_numerator,
            denominator: price_denominator
        };

        let option_vault = OptionVault<Asset, USDC, OPTION_COIN> {
            id: object::new(ctx),
            option_type,
            asset_balance: balance::zero<Asset>(),
            usdc_balance: balance::zero<USDC>(),
            exercise_price,
            expire_date,
            owner: ctx.sender(),
            treasury_cap,
            asset_decimals,
            usdc_decimals
        };

        dof::add(&mut marketplace.id, typename, option_vault);

        let vault_owner = VaultOwner {
            id: object::new(ctx),
            option_coin_type: typename,
            marketplace: object::uid_to_address(&marketplace.id)
        };

        transfer::transfer(vault_owner, tx_context::sender(ctx));
    }

    /// Get vault using owner's capability
    public(package) fun get_vault_from_marketplace_with_owner<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace,
        vault_owner: &VaultOwner
    ): &mut OptionVault<Asset, USDC, OPTION_COIN> {
        dof::borrow_mut(
            &mut marketplace.id,
            vault_owner.option_coin_type
        )
    }

    /// Get vault using option coin type
    public(package) fun get_vault_from_marketplace_with_name<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace
    ): &mut OptionVault<Asset, USDC, OPTION_COIN> {
        dof::borrow_mut(
            &mut marketplace.id,
            type_name::get<OPTION_COIN>()
        )
    }
    /// Helper function to adjust amounts based on decimal differences
    fun adjust_decimal_scale(
        amount: u64,
        from_decimals: u8,
        to_decimals: u8
    ): u64 {
        if (from_decimals > to_decimals) {
            amount / pow(10, from_decimals - to_decimals)
        } else {
            amount * pow(10, to_decimals - from_decimals)
        }
    }


    /// Common time checks
    public fun check_expire<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>,
        clock: &Clock
    ) {
        assert!(option_vault.expire_date > clock::timestamp_ms(clock), EExpired);
    }

    public fun check_exercise<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>,
        clock: &Clock
    ) {
        assert!(option_vault.expire_date < clock::timestamp_ms(clock), EExpired);
    }

    public fun check_withdrawal_period<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>,
        clock: &Clock
    ) {
        let current_time = clock::timestamp_ms(clock);
        let withdrawal_time = option_vault.expire_date + WITHDRAWAL_DELAY;
        assert!(current_time >= withdrawal_time, EWithdrawTooEarly);
    }


    /// Write covered call option
    /// option coin have the same decimal as the underlying asset!
    public entry fun write_covered_call<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace,
        vault_owner: &VaultOwner,
        clock: &Clock,
        asset: Coin<Asset>,
        ctx: &mut TxContext
    ) {
        let option_vault = get_vault_from_marketplace_with_owner<Asset, USDC, OPTION_COIN>(
            marketplace,
            vault_owner
        );
        
        assert!(option_vault.option_type == CALL_OPTION, EOptionType);
        check_expire(option_vault, clock);

        let asset_amount = asset.value();
        let option_coin = coin::mint(&mut option_vault.treasury_cap, asset_amount, ctx);

        option_vault.asset_balance.join(coin::into_balance(asset));
        transfer::public_transfer(option_coin, tx_context::sender(ctx));
    }

    /// Write covered put option
    public entry fun write_covered_put<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace,
        vault_owner: &VaultOwner,
        clock: &Clock,
        collateral: Coin<USDC>,
        option_amount: u64,
        ctx: &mut TxContext
    ) {
        let option_vault = get_vault_from_marketplace_with_owner<Asset, USDC, OPTION_COIN>(
            marketplace,
            vault_owner
        );
        
        assert!(option_vault.option_type == PUT_OPTION, EOptionType);
        check_expire(option_vault, clock);

        // Adjust option amount to USDC decimals for collateral calculation
        let adjusted_amount = adjust_decimal_scale(
            option_amount,
            option_vault.asset_decimals,
            option_vault.usdc_decimals
        );

        let required_collateral = (adjusted_amount * option_vault.exercise_price.numerator) / 
                                 option_vault.exercise_price.denominator;
        assert!(collateral.value() >= required_collateral, EInsufficientCollateral);

        // Option tokens are minted with asset decimals
        let option_coin = coin::mint(&mut option_vault.treasury_cap, option_amount, ctx);

        option_vault.usdc_balance.join(coin::into_balance(collateral));
        transfer::public_transfer(option_coin, tx_context::sender(ctx));
    }

    /// Exercise functions 
    public entry fun exercise_call<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace,
        clock: &Clock,
        option_coin: Coin<OPTION_COIN>,
        payment: Coin<USDC>,
        ctx: &mut TxContext
    ) {
        let option_vault = get_vault_from_marketplace_with_name<Asset, USDC, OPTION_COIN>(marketplace);
        assert!(option_vault.option_type == CALL_OPTION, EOptionType);
        check_exercise(option_vault, clock);

        let option_amount = option_coin.value();
        
        // Adjust option amount to USDC decimals for payment calculation
        let adjusted_amount = adjust_decimal_scale(
            option_amount,
            option_vault.asset_decimals,
            option_vault.usdc_decimals
        );

        let required_payment = (adjusted_amount * option_vault.exercise_price.numerator) / 
                            option_vault.exercise_price.denominator;

        assert!(payment.value() >= required_payment, EPriceInvalid);

        let assets = coin::from_balance(
            option_vault.asset_balance.split(option_amount),
            ctx
        );
        transfer::public_transfer(assets, tx_context::sender(ctx));

        option_vault.usdc_balance.join(coin::into_balance(payment));
        coin::burn(&mut option_vault.treasury_cap, option_coin);
    }


    public entry fun exercise_put<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace,
        clock: &Clock,
        option_coin: Coin<OPTION_COIN>,
        assets: Coin<Asset>,
        ctx: &mut TxContext
    ) {
        let option_vault = get_vault_from_marketplace_with_name<Asset, USDC, OPTION_COIN>(marketplace);
        assert!(option_vault.option_type == PUT_OPTION, EOptionType);
        check_exercise(option_vault, clock);

        let option_amount = option_coin.value();
        assert!(assets.value() == option_amount, EPriceInvalid);

        // Adjust option amount to USDC decimals for payout calculation
        let adjusted_amount = adjust_decimal_scale(
            option_amount,
            option_vault.asset_decimals,
            option_vault.usdc_decimals
        );

        let payout_amount = (adjusted_amount * option_vault.exercise_price.numerator) / 
                        option_vault.exercise_price.denominator;

        let payout = coin::from_balance(
            option_vault.usdc_balance.split(payout_amount),
            ctx
        );
        transfer::public_transfer(payout, tx_context::sender(ctx));

        option_vault.asset_balance.join(coin::into_balance(assets));
        coin::burn(&mut option_vault.treasury_cap, option_coin);
    }

    /// Withdraw tokens (before expiry) with decimal handling
    public entry fun withdraw_tokens<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace,
        vault_owner: &VaultOwner,
        clock: &Clock,
        option_coin: Coin<OPTION_COIN>,
        ctx: &mut TxContext
    ) {
        let option_vault = get_vault_from_marketplace_with_owner<Asset, USDC, OPTION_COIN>(
            marketplace,
            vault_owner
        );
        
        check_expire(option_vault, clock);
        let option_amount = option_coin.value();

        if (option_vault.option_type == CALL_OPTION) {
            // For call options, option amount equals asset amount directly
            let withdraw_coin = coin::from_balance(
                option_vault.asset_balance.split(option_amount),
                ctx
            );
            transfer::public_transfer(withdraw_coin, tx_context::sender(ctx));
        } else {
            // For put options, adjust for decimal differences
            let adjusted_amount = adjust_decimal_scale(
                option_amount,
                option_vault.asset_decimals,
                option_vault.usdc_decimals
            );

            // Calculate collateral amount with decimal-adjusted values
            let collateral_amount = (adjusted_amount * option_vault.exercise_price.numerator) / 
                                option_vault.exercise_price.denominator;

            let withdraw_coin = coin::from_balance(
                option_vault.usdc_balance.split(collateral_amount),
                ctx
            );
            transfer::public_transfer(withdraw_coin, tx_context::sender(ctx));
        };

        coin::burn(&mut option_vault.treasury_cap, option_coin);
    }

    /// Claim proceeds after expiry
    public entry fun claim_proceeds<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace,
        vault_owner: &VaultOwner,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let option_vault = get_vault_from_marketplace_with_owner<Asset, USDC, OPTION_COIN>(
            marketplace,
            vault_owner
        );
        
        check_exercise(option_vault, clock);

        if (option_vault.option_type == CALL_OPTION) {
            if (option_vault.usdc_balance.value() > 0) {
                let proceeds = coin::from_balance(
                    option_vault.usdc_balance.withdraw_all(),
                    ctx
                );
                transfer::public_transfer(proceeds, option_vault.owner);
            };
        } else {
            if (option_vault.asset_balance.value() > 0) {
                let assets = coin::from_balance(
                    option_vault.asset_balance.withdraw_all(),
                    ctx
                );
                transfer::public_transfer(assets, option_vault.owner);
            };
        };
    }

    /// Final withdrawal after waiting period
    public entry fun withdraw_remaining<Asset, USDC, OPTION_COIN>(
        marketplace: &mut Marketplace,
        vault_owner: &VaultOwner,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let option_vault = get_vault_from_marketplace_with_owner<Asset, USDC, OPTION_COIN>(
            marketplace,
            vault_owner
        );
        
        assert!(tx_context::sender(ctx) == option_vault.owner, EOwnerError);
        check_withdrawal_period(option_vault, clock);

        if (option_vault.option_type == CALL_OPTION) {
            if (option_vault.asset_balance.value() > 0) {
                let remaining = coin::from_balance(
                    option_vault.asset_balance.withdraw_all(),
                    ctx
                );
                transfer::public_transfer(remaining, option_vault.owner);
            };
        } else {
            if (option_vault.usdc_balance.value() > 0) {
                let remaining = coin::from_balance(
                    option_vault.usdc_balance.withdraw_all(),
                    ctx
                );
                transfer::public_transfer(remaining, option_vault.owner);
            };
        };
    }

    /// Utility functions
    public fun get_asset_balance<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>
    ): u64 {
        option_vault.asset_balance.value()
    }

    public fun get_usdc_balance<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>
    ): u64 {
        option_vault.usdc_balance.value()
    }

    public fun get_option_type<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>
    ): u8 {
        option_vault.option_type
    }

    public fun get_exercise_price<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>
    ): ExercisePrice {
        option_vault.exercise_price
    }

    public fun get_expire_date<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>
    ): u64 {
        option_vault.expire_date
    }

    public fun get_owner<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>
    ): address {
        option_vault.owner
    }

    /// Check if withdrawal period is active
    public fun is_withdrawal_period_active<Asset, USDC, OPTION_COIN>(
        option_vault: &OptionVault<Asset, USDC, OPTION_COIN>,
        clock: &Clock
    ): bool {
        clock::timestamp_ms(clock) >= (option_vault.expire_date + WITHDRAWAL_DELAY)
    }
