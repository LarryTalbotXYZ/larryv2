// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::lending {
    use std::option;
    use sui::balance;
    use sui::coin;
    use sui::object;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::dynamic_field;
    use sui::clock::Clock;
    use larry_talbot::larry_token::{Self, LARRY};
    use larry_talbot::admin::{Self, Config};
    use larry_talbot::events;
    use larry_talbot::math;
    use larry_talbot::trading::{Self, Vault};
    
    /// Loan information
    struct Loan has store {
        collateral: u64,        // LARRY tokens staked as collateral
        borrowed: u64,          // SUI borrowed
        end_date: u64,          // Loan expiration timestamp
        number_of_days: u64     // Loan duration in days
    }
    
    /// Loan data tracking by date
    struct LoanData has key {
        id: object::UID,
        borrowed_by_date: u64,
        collateral_by_date: u64
    }
    
    /// Global loan statistics
    struct LoanStats has key {
        id: object::UID,
        total_borrowed: u64,
        total_collateral: u64,
        last_liquidation_date: u64
    }
    
    /// Collateral wrapper for LARRY tokens
    struct Collateral has key {
        id: object::UID,
        coin: coin::Coin<LARRY>
    }
    
    /// Constants
    const MIN_AMOUNT: u64 = 1000;
    const COLLATERALIZATION_RATE: u64 = 101; // 101% collateralization
    
    /// Initialize loan statistics
    public fun create_loan_stats(ctx: &mut TxContext): LoanStats {
        LoanStats {
            id: sui::object::new(ctx),
            total_borrowed: 0,
            total_collateral: 0,
            last_liquidation_date: math::get_midnight_timestamp(tx_context::epoch(ctx))
        }
    }
    
    /// Create loan data tracking object
    public fun create_loan_data(ctx: &mut TxContext): LoanData {
        LoanData {
            id: sui::object::new(ctx),
            borrowed_by_date: 0,
            collateral_by_date: 0
        }
    }
    
    /// Leverage trading function
    public entry fun leverage(
        vault: &mut Vault,
        config: &Config,
        loan_stats: &mut LoanStats,
        larry_mint_cap: &larry_token::MintCap,
        larry_treasury_cap: &larry_token::TreasuryCap,
        fee_address: address,
        sui_coins: vector<Coin<SUI>>,
        number_of_days: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if trading is started
        assert!(admin::is_started(config), 0);
        
        // Validate loan duration
        assert!(number_of_days < 366, 1); // Max 365 days
        
        // Get total SUI value
        let total_sui = coin::total_balance(sui_coins);
        
        // Calculate fees
        let leverage_fee_pct = admin::get_buy_fee_leverage(config) as u64;
        let mint_fee = (total_sui * leverage_fee_pct) / 10000;
        let interest = math::get_interest_fee(total_sui, number_of_days);
        let total_fee = mint_fee + interest;
        
        // Calculate user SUI amount after fees
        let user_sui = total_sui - total_fee;
        
        // Calculate fee distribution (30% to team)
        let fee_address_amount = (total_fee * 3) / 10;
        let user_borrow = (user_sui * 99) / 100; // 99% to user
        let over_collateralization_amount = user_sui / 100; // 1% over-collateralization
        let sub_value = fee_address_amount + over_collateralization_amount;
        
        // Validate fee amount
        assert!(fee_address_amount > MIN_AMOUNT, 2);
        
        // Calculate LARRY amount to mint
        let pool_info = trading::get_pool_info(vault, larry_treasury_cap);
        let user_larry = math::eth_to_larry_leverage(user_sui, sub_value, pool_info.sui_balance, pool_info.larry_supply);
        
        // Mint LARRY tokens for contract
        let larry_coins = larry_token::mint(larry_mint_cap, user_larry, ctx);
        
        // Create collateral wrapper
        let collateral = Collateral {
            id: sui::object::new(ctx),
            coin: larry_coins
        };
        
        // Split SUI for fee
        let (fee_coins, remaining_sui) = if (coin::total_balance(sui_coins) > fee_address_amount) {
            coin::split_vec(sui_coins, fee_address_amount)
        } else {
            (sui_coins, vector[]) // No remaining if exact amount
        };
        
        // Send fee to team
        transfer::public_transfer(fee_coins, fee_address);
        events::emit_sui_sent(fee_address, fee_address_amount);
        
        // Add remaining SUI to vault
        if (!vector::is_empty(remaining_sui)) {
            let sui_coin = coin::from_vec(remaining_sui);
            let sui_balance = coin::into_balance(sui_coin);
            let vault_balance = &mut vault.balance;
            balance::join(vault_balance, sui_balance);
        }
        
        // Send borrowed SUI to user
        let borrowed_sui_coins = balance::split(&mut vault.balance, user_borrow);
        transfer::public_transfer(borrowed_sui_coins, tx_context::sender(ctx));
        
        // Calculate loan end date
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let end_date = math::get_midnight_timestamp((number_of_days * 86400) + current_time);
        
        // Create loan record
        let loan = Loan {
            collateral: user_larry,
            borrowed: user_borrow,
            end_date,
            number_of_days
        };
        
        // Store loan as dynamic field of user account
        dynamic_field::add(tx_context::sender(ctx), end_date, loan);
        
        // Update loan statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed + user_borrow;
        loan_stats.total_collateral = loan_stats.total_collateral + user_larry;
        
        // Update loan data by date
        // In a real implementation, we would store this in a more structured way
        events::emit_loan_data_update(
            loan_stats.total_collateral,
            loan_stats.total_borrowed,
            loan_stats.total_borrowed,
            loan_stats.total_collateral
        );
    }
    
    /// Borrow SUI with LARRY collateral
    public entry fun borrow(
        vault: &mut Vault,
        config: &Config,
        loan_stats: &mut LoanStats,
        fee_address: address,
        larry_coins: vector<Coin<LARRY>>,
        sui_amount: u64,
        number_of_days: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate parameters
        assert!(number_of_days < 366, 0); // Max 365 days
        assert!(sui_amount != 0, 1); // Must borrow more than 0
        
        // Check if user already has an active loan
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        // In a real implementation, we would check if user has existing loans
        
        // Calculate interest fee
        let interest_fee = math::get_interest_fee(sui_amount, number_of_days);
        let fee_address_fee = (interest_fee * 3) / 10; // 30% to team
        
        // Validate fee amount
        assert!(fee_address_fee > MIN_AMOUNT, 2);
        
        // Calculate user net amount
        let user_amount = sui_amount - interest_fee;
        
        // Calculate required LARRY collateral (101% of borrowed amount)
        // This would require getting current LARRY/SUI price
        // For simplicity, we'll use a fixed ratio
        let required_larry = (sui_amount * COLLATERALIZATION_RATE) / 100;
        
        // Check if user provided enough LARRY
        let provided_larry = coin::total_balance(larry_coins);
        assert!(provided_larry >= required_larry, 3);
        
        // Create collateral wrapper
        let larry_coin = coin::from_vec(larry_coins);
        let collateral = Collateral {
            id: sui::object::new(ctx),
            coin: larry_coin
        };
        
        // Transfer collateral to contract
        transfer::public_transfer(collateral, tx_context::sender(ctx));
        
        // Send borrowed SUI to user
        let borrowed_sui_coins = balance::split(&mut vault.balance, user_amount);
        transfer::public_transfer(borrowed_sui_coins, tx_context::sender(ctx));
        
        // Send fee to team
        let fee_sui_coins = balance::split(&mut vault.balance, fee_address_fee);
        transfer::public_transfer(fee_sui_coins, fee_address);
        events::emit_sui_sent(fee_address, fee_address_fee);
        
        // Calculate loan end date
        let end_date = math::get_midnight_timestamp((number_of_days * 86400) + current_time);
        
        // Create loan record
        let loan = Loan {
            collateral: required_larry,
            borrowed: user_amount,
            end_date,
            number_of_days
        };
        
        // Store loan as dynamic field of user account
        dynamic_field::add(tx_context::sender(ctx), end_date, loan);
        
        // Update loan statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed + user_amount;
        loan_stats.total_collateral = loan_stats.total_collateral + required_larry;
        
        // Update loan data by date
        events::emit_loan_data_update(
            loan_stats.total_collateral,
            loan_stats.total_borrowed,
            loan_stats.total_borrowed,
            loan_stats.total_collateral
        );
    }
    
    /// Close a loan position
    public entry fun close_position(
        vault: &mut Vault,
        loan_stats: &mut LoanStats,
        larry_burn_cap: &larry_token::BurnCap,
        sui_coins: vector<Coin<SUI>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Get total SUI repaid
        let total_sui = coin::total_balance(sui_coins);
        
        // Find user's loan
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let midnight = math::get_midnight_timestamp(current_time);
        
        // In a real implementation, we would retrieve the loan from dynamic fields
        // For this example, we'll assume the loan exists and matches the amount
        
        // Burn user's collateral LARRY tokens
        // In a real implementation, we would retrieve the actual collateral amount
        
        // Return user's collateral
        // In a real implementation, we would transfer the actual collateral back
        
        // Update loan statistics
        // In a real implementation, we would update with actual values
        
        // Remove loan record
        // In a real implementation, we would remove from dynamic fields
    }
    
    /// Get loan information for an address
    public fun get_loan_info(addr: address, date: u64): Option<Loan> {
        dynamic_field::borrow<address, u64, Loan>(addr, date)
    }
    
    /// Check if loan is expired
    public fun is_loan_expired(loan: &Loan, clock: &Clock): bool {
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        current_time > loan.end_date
    }
}
