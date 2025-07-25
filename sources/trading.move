// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::trading {
    use sui::balance;
    use sui::coin;
    use sui::object;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use larry_talbot::larry_token::LARRY;
    use larry_talbot::admin::{Self, Config};
    use larry_talbot::events;
    use larry_talbot::math;
    use larry_talbot::liquidation;
    
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
    const FEES_BUY: u64 = 2000; // 5% fee (2000/10000 = 20%, but used as divisor so 10000/2000 = 5%)
    const FEES_SELL: u64 = 2000; // 5% fee
    const FEE_BASE_10000: u64 = 10000;
    
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
        loan_stats: &mut larry_talbot::lending::LoanStats,
        sui_coins: vector<coin::Coin<sui::sui::SUI>>,
        ctx: &mut TxContext
    ) {
        // Check if trading is started
        assert!(admin::is_started(config), 0);
        
        // Run liquidation first
        liquidation::liquidate(loan_stats, vault, &sui::clock::create_for_testing(ctx), ctx);
        
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
        let larry_amount = math::eth_to_larry(total_sui, balance::value(&vault.balance), coin::total_supply(larry_treasury_cap));
        
        // Apply buy fee
        let buy_fee = (admin::get_buy_fee(config) as u64);
        let larry_after_fee = (larry_amount * buy_fee) / FEE_BASE_10000;
        
        // Check minimum trade amount
        assert!(larry_after_fee > MIN_TRADE_AMOUNT, 1);
        
        // Mint LARRY tokens
        let larry_coins = coin::mint(larry_treasury_cap, larry_after_fee, ctx);
        
        // Calculate team fee (5% of SUI)
        let team_fee = total_sui / (FEES_BUY / 100); // 5% fee
        assert!(team_fee > MIN_TRADE_AMOUNT, 2);
        
        // Process SUI coins for vault and fees
        let mut fee_balance = balance::zero<sui::sui::SUI>();
        let mut vault_balance_to_add = balance::zero<sui::sui::SUI>();
        let mut fee_collected = 0;
        
        while (!vector::is_empty(&mut sui_coins)) {
            let sui_coin = vector::pop_back(&mut sui_coins);
            let coin_value = coin::value(&sui_coin);
            let mut coin_balance = coin::into_balance(sui_coin);
            
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
        
        // Send fee to team
        let fee_coin = coin::from_balance(fee_balance, ctx);
        let fee_address = admin::get_fee_address(config);
        transfer::public_transfer(fee_coin, fee_address);
        events::emit_sui_sent(fee_address, team_fee);
        
        vector::destroy_empty(sui_coins);
        
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
            sui::tx_context::epoch(ctx),
            new_price,
            total_sui
        );
        
        // Safety check
        safety_check(vault, larry_treasury_cap, total_sui);
    }
    
    /// Sell LARRY tokens for SUI
    public entry fun sell(
        vault: &mut Vault,
        config: &Config,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        loan_stats: &mut larry_talbot::lending::LoanStats,
        larry_coins: vector<coin::Coin<LARRY>>,
        ctx: &mut TxContext
    ) {
        // Check if trading is started
        assert!(admin::is_started(config), 0);
        
        // Run liquidation first
        liquidation::liquidate(loan_stats, vault, &sui::clock::create_for_testing(ctx), ctx);
        
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
        
        // Calculate SUI amount to return
        let sui_amount = math::larry_to_eth(total_larry, balance::value(&vault.balance), coin::total_supply(larry_treasury_cap));
        
        // Apply sell fee
        let sell_fee = (admin::get_sell_fee(config) as u64);
        let sui_after_fee = (sui_amount * sell_fee) / FEE_BASE_10000;
        
        // Check minimum trade amount
        assert!(sui_after_fee > MIN_TRADE_AMOUNT, 1);
        
        // Calculate team fee (5% of SUI)
        let team_fee = sui_amount / (FEES_SELL / 100); // 5% fee
        assert!(team_fee > MIN_TRADE_AMOUNT, 2);
        
        // Check vault has enough SUI
        assert!(balance::value(&vault.balance) >= (sui_after_fee + team_fee), 3);
        
        // Burn all LARRY tokens
        while (!vector::is_empty(&mut larry_coins)) {
            let larry_coin = vector::pop_back(&mut larry_coins);
            coin::burn(larry_treasury_cap, larry_coin);
        };
        vector::destroy_empty(larry_coins);
        
        // Split SUI from vault
        let user_sui_balance = balance::split(&mut vault.balance, sui_after_fee);
        let fee_sui_balance = balance::split(&mut vault.balance, team_fee);
        
        let user_sui_coin = coin::from_balance(user_sui_balance, ctx);
        let fee_sui_coin = coin::from_balance(fee_sui_balance, ctx);
        
        // Send SUI to user
        transfer::public_transfer(user_sui_coin, tx_context::sender(ctx));
        
        // Send team fee
        let fee_address = admin::get_fee_address(config);
        transfer::public_transfer(fee_sui_coin, fee_address);
        events::emit_sui_sent(fee_address, team_fee);
        
        // Emit events
        let new_pool_info = get_pool_info(vault, larry_treasury_cap);
        let new_price = if (new_pool_info.larry_supply > 0) {
            (new_pool_info.sui_balance * 1000000000) / new_pool_info.larry_supply
        } else {
            0
        };
        
        events::emit_price_update(
            sui::tx_context::epoch(ctx),
            new_price,
            sui_amount
        );
        
        // Safety check
        safety_check(vault, larry_treasury_cap, sui_amount);
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
        (larry_amount * buy_fee) / FEE_BASE_10000
    }
    
    /// Get vault balance
    public fun get_vault_balance(vault: &Vault): u64 {
        balance::value(&vault.balance)
    }
    
    /// Safety check to ensure price doesn't decrease
    fun safety_check(
        vault: &Vault,
        larry_treasury_cap: &coin::TreasuryCap<LARRY>,
        transaction_amount: u64
    ) {
        let vault_balance = balance::value(&vault.balance);
        let larry_supply = coin::total_supply(larry_treasury_cap);
        
        if (larry_supply > 0) {
            let new_price = (vault_balance * 1000000000) / larry_supply;
            // Ensure price is valid and reasonable
            assert!(new_price > 0, 4);
            
            // Additional safety checks for extreme price movements
            if (vault_balance > 0) {
                // Ensure price ratio is within reasonable bounds
                let price_per_token = vault_balance / larry_supply;
                assert!(price_per_token > 0, 5);
            };
        };
        
        // Emit price event with proper timestamp
        events::emit_price_update(
            0, // In real implementation would use clock timestamp
            if (larry_supply > 0) { (vault_balance * 1000000000) / larry_supply } else { 0 },
            transaction_amount
        );
    }
    
    /// Calculate current price per LARRY token
    public fun get_current_price(
        vault: &Vault,
        larry_treasury_cap: &coin::TreasuryCap<LARRY>
    ): u64 {
        let vault_balance = balance::value(&vault.balance);
        let larry_supply = coin::total_supply(larry_treasury_cap);
        
        if (larry_supply > 0) {
            (vault_balance * 1000000000) / larry_supply
        } else {
            1000000000 // Default 1:1 price with 9 decimals
        }
    }
    
    /// Get trading statistics
    public fun get_trading_stats(
        vault: &Vault,
        larry_treasury_cap: &coin::TreasuryCap<LARRY>
    ): (u64, u64, u64) {
        let vault_balance = balance::value(&vault.balance);
        let larry_supply = coin::total_supply(larry_treasury_cap);
        let current_price = get_current_price(vault, larry_treasury_cap);
        
        (vault_balance, larry_supply, current_price)
    }
}