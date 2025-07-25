// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::trading {
    use sui::balance;
    use sui::coin;
    use sui::object;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::Clock;
    use std::vector;
    use larry_talbot::larry_token::LARRY;
    use larry_talbot::admin::{Self, Config};
    use larry_talbot::events;
    use larry_talbot::math;
    
    /// Vault to hold SUI backing the LARRY token
    struct Vault has key {
        id: object::UID,
        balance: balance::Balance<sui::sui::SUI>
    }
    
    /// Pool information for price calculations
    struct PoolInfo has copy, drop, store {
        sui_balance: u64,
        larry_supply: u64
    }
    
    /// Constants
    const MIN_TRADE_AMOUNT: u64 = 1000; // Minimum trade amount
    
    /// Initialize the trading vault
    public fun create_vault(ctx: &mut TxContext): Vault {
        Vault {
            id: object::new(ctx),
            balance: balance::zero()
        }
    }
    
    /// Get current pool information
    public fun get_pool_info(vault: &Vault, larry_treasury_cap: &coin::TreasuryCap<LARRY>): PoolInfo {
        let sui_balance = balance::value(&vault.balance);
        let larry_supply = coin::total_supply(larry_treasury_cap);
        PoolInfo { sui_balance, larry_supply }
    }
    
    /// Buy LARRY tokens with SUI
    public entry fun buy(
        vault: &mut Vault,
        config: &Config,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        fee_address: address,
        sui_coins: vector<coin::Coin<sui::sui::SUI>>,
        ctx: &mut TxContext
    ) {
        // Check if trading is started
        assert!(admin::is_started(config), 0);
        
        // Combine SUI coins and get total value
        let total_sui = {
            let mut sum = 0;
            let mut i = 0;
            while (i < vector::length(&sui_coins)) {
                sum = sum + coin::value(vector::borrow(&sui_coins, i));
                i = i + 1;
            };
            sum
        };
        
        // Calculate LARRY amount to mint
        let pool_info = get_pool_info(vault, larry_treasury_cap);
        let larry_amount = math::eth_to_larry(total_sui, pool_info.sui_balance, pool_info.larry_supply);
        
        // Apply buy fee
        let buy_fee = (admin::get_buy_fee(config) as u64);
        let larry_after_fee = (larry_amount * buy_fee) / 10000;
        
        // Check minimum trade amount
        assert!(larry_after_fee > MIN_TRADE_AMOUNT, 1);
        
        // Mint LARRY tokens
        let larry_coins = coin::mint(larry_treasury_cap, larry_after_fee, ctx);
        
        // Calculate team fee (5% of SUI)
        let team_fee = total_sui / 20; // 5% fee
        assert!(team_fee > MIN_TRADE_AMOUNT, 2);
        
        // Send team fee from first coins
        let fee_balance = balance::zero<sui::sui::SUI>();
        let vault_balance_to_add = balance::zero<sui::sui::SUI>();
        let mut fee_collected = 0;
        
        while (!vector::is_empty(&mut sui_coins)) {
            let sui_coin = vector::pop_back(&mut sui_coins);
            let coin_value = coin::value(&sui_coin);
            let coin_balance = coin::into_balance(sui_coin);
            
            if (fee_collected < team_fee) {
                let fee_needed = team_fee - fee_collected;
                if (coin_value <= fee_needed) {
                    balance::join(&mut fee_balance, coin_balance);
                    fee_collected = fee_collected + coin_value;
                } else {
                    let fee_part = balance::split(&mut coin_balance, fee_needed);
                    balance::join(&mut fee_balance, fee_part);
                    balance::join(&mut vault_balance_to_add, coin_balance);
                    fee_collected = fee_collected + fee_needed;
                }
            } else {
                balance::join(&mut vault_balance_to_add, coin_balance);
            }
        };
        
        // Add to vault
        balance::join(&mut vault.balance, vault_balance_to_add);
        
        // Send fee
        let fee_coin = coin::from_balance(fee_balance, ctx);
        transfer::public_transfer(fee_coin, fee_address);
        
        vector::destroy_empty(sui_coins);
        events::emit_sui_sent(fee_address, team_fee);
        
        // Transfer LARRY to buyer
        transfer::public_transfer(larry_coins, tx_context::sender(ctx));
        
        // Emit events
        let new_pool_info = get_pool_info(vault, larry_treasury_cap);
        let new_price = if (new_pool_info.larry_supply > 0) {
            (new_pool_info.sui_balance * 1000000000) / new_pool_info.larry_supply // Price with 9 decimals
        } else {
            0
        };
        
        events::emit_price_update(
            0, // timestamp placeholder
            new_price,
            total_sui
        );
    }
    
    /// Sell LARRY tokens for SUI
    public entry fun sell(
        vault: &mut Vault,
        config: &Config,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        fee_address: address,
        larry_coins: vector<coin::Coin<LARRY>>,
        ctx: &mut TxContext
    ) {
        // Check if trading is started
        assert!(admin::is_started(config), 0);
        
        // Get total LARRY value
        let total_larry = {
            let mut sum = 0;
            let mut i = 0;
            while (i < vector::length(&larry_coins)) {
                sum = sum + coin::value(vector::borrow(&larry_coins, i));
                i = i + 1;
            };
            sum
        };
        
        // Burn all LARRY tokens
        while (!vector::is_empty(&mut larry_coins)) {
            let larry_coin = vector::pop_back(&mut larry_coins);
            coin::burn(larry_treasury_cap, larry_coin);
        };
        vector::destroy_empty(larry_coins);
        
        // Calculate SUI amount to return
        let pool_info = get_pool_info(vault, larry_treasury_cap);
        let sui_amount = math::larry_to_eth(total_larry, pool_info.sui_balance, pool_info.larry_supply);
        
        // Apply sell fee
        let sell_fee = (admin::get_sell_fee(config) as u64);
        let sui_after_fee = (sui_amount * sell_fee) / 10000;
        
        // Check minimum trade amount
        assert!(sui_after_fee > MIN_TRADE_AMOUNT, 1);
        
        // Calculate team fee (5% of SUI)
        let team_fee = sui_amount / 20; // 5% fee
        assert!(team_fee > MIN_TRADE_AMOUNT, 2);
        
        // Check vault has enough SUI
        assert!(balance::value(&vault.balance) >= (sui_after_fee + team_fee), 3);
        
        // Split SUI from vault
        let user_sui_balance = balance::split(&mut vault.balance, sui_after_fee);
        let fee_sui_balance = balance::split(&mut vault.balance, team_fee);
        
        let user_sui_coin = coin::from_balance(user_sui_balance, ctx);
        let fee_sui_coin = coin::from_balance(fee_sui_balance, ctx);
        
        // Send SUI to user
        transfer::public_transfer(user_sui_coin, tx_context::sender(ctx));
        
        // Send team fee
        transfer::public_transfer(fee_sui_coin, fee_address);
        events::emit_sui_sent(fee_address, team_fee);
        
        // Emit events
        let new_pool_info = get_pool_info(vault, larry_treasury_cap);
        let new_price = if (new_pool_info.larry_supply > 0) {
            (new_pool_info.sui_balance * 1000000000) / new_pool_info.larry_supply // Price with 9 decimals
        } else {
            0
        };
        
        events::emit_price_update(
            0, // timestamp placeholder
            new_price,
            sui_amount
        );
    }
    
    /// Get buy amount for a given SUI amount
    public fun get_buy_amount(
        sui_amount: u64,
        vault: &Vault,
        larry_treasury_cap: &coin::TreasuryCap<LARRY>,
        config: &Config
    ): u64 {
        let pool_info = get_pool_info(vault, larry_treasury_cap);
        let larry_amount = math::eth_to_larry_no_trade(sui_amount, pool_info.sui_balance, pool_info.larry_supply);
        
        // Apply buy fee
        let buy_fee = (admin::get_buy_fee(config) as u64);
        (larry_amount * buy_fee) / 10000
    }
    
    /// Get vault balance
    public fun get_vault_balance(vault: &Vault): u64 {
        balance::value(&vault.balance)
    }
}
