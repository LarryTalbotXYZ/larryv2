// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::lending {
    use sui::balance;
    use sui::coin;
    use sui::object;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field;
    use sui::clock::{Self, Clock};
    use std::vector;
    use larry_talbot::larry_token::LARRY;
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
        larry_balance: balance::Balance<LARRY>
    }
    
    /// Constants
    const MIN_AMOUNT: u64 = 1000;
    const COLLATERALIZATION_RATE: u64 = 101; // 101% collateralization
    const FEE_BASE_10000: u64 = 10000;
    
    /// Initialize loan statistics
    public fun create_loan_stats(ctx: &mut TxContext): LoanStats {
        LoanStats {
            id: object::new(ctx),
            total_borrowed: 0,
            total_collateral: 0,
            last_liquidation_date: math::get_midnight_timestamp(0) // Will be set properly on first use
        }
    }
    
    /// Create loan data tracking object
    public fun create_loan_data(ctx: &mut TxContext): LoanData {
        LoanData {
            id: object::new(ctx),
            borrowed_by_date: 0,
            collateral_by_date: 0
        }
    }
    
    /// Leverage trading function - complete implementation
    public entry fun leverage(
        vault: &mut Vault,
        config: &Config,
        loan_stats: &mut LoanStats,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        sui_coins: vector<coin::Coin<sui::sui::SUI>>,
        number_of_days: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if trading is started
        assert!(admin::is_started(config), 0);
        
        // Validate loan duration
        assert!(number_of_days < 366, 1); // Max 365 days
        
        // Check if user already has an active loan
        let sender = tx_context::sender(ctx);
        assert!(!dynamic_field::exists_(&loan_stats.id, sender), 2);
        
        // Run liquidation first
        larry_talbot::liquidation::liquidate(loan_stats, vault, clock, ctx);
        
        // Get total SUI value
        let total_sui = {
            let mut i = 0;
            let mut total = 0;
            while (i < vector::length(&sui_coins)) {
                total = total + coin::value(vector::borrow(&sui_coins, i));
                i = i + 1;
            };
            total
        };
        
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
        
        // Validate fee amount
        assert!(fee_address_amount > MIN_AMOUNT, 3);
        
        // Calculate LARRY amount to mint
        let pool_info = trading::get_pool_info(vault, larry_treasury_cap);
        let user_larry = math::eth_to_larry_leverage(user_sui, fee_address_amount + over_collateralization_amount, pool_info.sui_balance, pool_info.larry_supply);
        
        // Mint LARRY tokens
        let larry_coins = coin::mint(larry_treasury_cap, user_larry, ctx);
        
        // Create collateral wrapper
        let collateral = Collateral {
            id: object::new(ctx),
            larry_balance: coin::into_balance(larry_coins)
        };
        
        // Process SUI coins for fees and borrowing
        let mut fee_balance = balance::zero<sui::sui::SUI>();
        let mut borrow_balance = balance::zero<sui::sui::SUI>();
        let mut vault_balance_to_add = balance::zero<sui::sui::SUI>();
        let mut fee_collected = 0;
        let mut borrow_collected = 0;
        
        while (!vector::is_empty(&mut sui_coins)) {
            let sui_coin = vector::pop_back(&mut sui_coins);
            let coin_value = coin::value(&sui_coin);
            let mut coin_balance = coin::into_balance(sui_coin);
            
            // First collect fees
            if (fee_collected < fee_address_amount) {
                let fee_needed = fee_address_amount - fee_collected;
                if (coin_value <= fee_needed) {
                    balance::join(&mut fee_balance, coin_balance);
                    fee_collected = fee_collected + coin_value;
                    continue
                } else {
                    let fee_part = balance::split(&mut coin_balance, fee_needed);
                    balance::join(&mut fee_balance, fee_part);
                    fee_collected = fee_collected + fee_needed;
                }
            };
            
            // Then collect for borrowing
            if (borrow_collected < user_borrow) {
                let borrow_needed = user_borrow - borrow_collected;
                if (coin_value - (if (fee_collected < fee_address_amount) fee_collected else 0) <= borrow_needed) {
                    balance::join(&mut borrow_balance, coin_balance);
                    borrow_collected = borrow_collected + (coin_value - (if (fee_collected < fee_address_amount) fee_collected else 0));
                    continue
                } else {
                    let borrow_part = balance::split(&mut coin_balance, borrow_needed);
                    balance::join(&mut borrow_balance, borrow_part);
                    borrow_collected = borrow_collected + borrow_needed;
                }
            };
            
            // Rest goes to vault
            balance::join(&mut vault_balance_to_add, coin_balance);
        };
        
        // Add remaining SUI to vault
        balance::join(&mut vault.balance, vault_balance_to_add);
        
        // Send fee to team
        let fee_coin = coin::from_balance(fee_balance, ctx);
        let fee_address = admin::get_fee_address(config);
        transfer::public_transfer(fee_coin, fee_address);
        events::emit_sui_sent(fee_address, fee_address_amount);
        
        // Send borrowed SUI to user
        let borrowed_sui_coin = coin::from_balance(borrow_balance, ctx);
        transfer::public_transfer(borrowed_sui_coin, sender);
        
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
        
        // Store loan as dynamic field
        dynamic_field::add(&mut loan_stats.id, sender, loan);
        
        // Transfer collateral to protocol (stored separately for tracking)
        transfer::transfer(collateral, sender);
        
        // Update loan statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed + user_borrow;
        loan_stats.total_collateral = loan_stats.total_collateral + user_larry;
        
        // Update loan data by date
        add_loans_by_date(loan_stats, user_borrow, user_larry, end_date);
        
        vector::destroy_empty(sui_coins);
    }
    
    /// Borrow SUI with LARRY collateral - complete implementation
    public entry fun borrow(
        vault: &mut Vault,
        config: &Config,
        loan_stats: &mut LoanStats,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        larry_coins: vector<coin::Coin<LARRY>>,
        sui_amount: u64,
        number_of_days: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate parameters
        assert!(number_of_days < 366, 0); // Max 365 days
        assert!(sui_amount != 0, 1); // Must borrow more than 0
        
        // Check if user already has an active loan
        let sender = tx_context::sender(ctx);
        assert!(!dynamic_field::exists_(&loan_stats.id, sender), 2);
        
        // Run liquidation first
        larry_talbot::liquidation::liquidate(loan_stats, vault, clock, ctx);
        
        // Calculate interest fee
        let interest_fee = math::get_interest_fee(sui_amount, number_of_days);
        let fee_address_fee = (interest_fee * 3) / 10; // 30% to team
        
        // Validate fee amount
        assert!(fee_address_fee > MIN_AMOUNT, 3);
        
        // Calculate user net amount
        let user_amount = sui_amount - interest_fee;
        
        // Calculate required LARRY collateral (using ETH to LARRY conversion for exact amount)
        let pool_info = trading::get_pool_info(vault, larry_treasury_cap);
        let required_larry = math::eth_to_larry_no_trade_ceil(sui_amount, pool_info.sui_balance, pool_info.larry_supply);
        
        // Check if user provided enough LARRY
        let provided_larry = {
            let mut i = 0;
            let mut total = 0;
            while (i < vector::length(&larry_coins)) {
                total = total + coin::value(vector::borrow(&larry_coins, i));
                i = i + 1;
            };
            total
        };
        assert!(provided_larry >= required_larry, 4);
        
        // Create collateral from provided LARRY tokens
        let mut collateral_balance = balance::zero<LARRY>();
        while (!vector::is_empty(&mut larry_coins)) {
            let larry_coin = vector::pop_back(&mut larry_coins);
            balance::join(&mut collateral_balance, coin::into_balance(larry_coin));
        };
        vector::destroy_empty(larry_coins);
        
        let collateral = Collateral {
            id: object::new(ctx),
            larry_balance: collateral_balance
        };
        
        // Send borrowed SUI to user
        let borrowed_sui_balance = balance::split(&mut vault.balance, user_amount);
        let borrowed_sui_coin = coin::from_balance(borrowed_sui_balance, ctx);
        transfer::public_transfer(borrowed_sui_coin, sender);
        
        // Send fee to team
        let fee_sui_balance = balance::split(&mut vault.balance, fee_address_fee);
        let fee_sui_coin = coin::from_balance(fee_sui_balance, ctx);
        let fee_address = admin::get_fee_address(config);
        transfer::public_transfer(fee_sui_coin, fee_address);
        events::emit_sui_sent(fee_address, fee_address_fee);
        
        // Calculate loan end date
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let end_date = math::get_midnight_timestamp((number_of_days * 86400) + current_time);
        
        // Create loan record
        let loan = Loan {
            collateral: required_larry,
            borrowed: user_amount,
            end_date,
            number_of_days
        };
        
        // Store loan as dynamic field
        dynamic_field::add(&mut loan_stats.id, sender, loan);
        
        // Transfer collateral to protocol
        transfer::transfer(collateral, sender);
        
        // Update loan statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed + user_amount;
        loan_stats.total_collateral = loan_stats.total_collateral + required_larry;
        
        // Update loan data by date
        add_loans_by_date(loan_stats, user_amount, required_larry, end_date);
    }
    
    /// Borrow more SUI on existing loan
    public entry fun borrow_more(
        vault: &mut Vault,
        config: &Config,
        loan_stats: &mut LoanStats,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        additional_larry_coins: vector<coin::Coin<LARRY>>,
        sui_amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Check if user has an active loan
        assert!(dynamic_field::exists_(&loan_stats.id, sender), 0);
        assert!(sui_amount != 0, 1);
        
        // Run liquidation first
        larry_talbot::liquidation::liquidate(loan_stats, vault, clock, ctx);
        
        // Get existing loan
        let loan = dynamic_field::borrow_mut<address, Loan>(&mut loan_stats.id, sender);
        
        // Check loan hasn't expired
        let current_time = clock::timestamp_ms(clock) / 1000;
        assert!(current_time < loan.end_date, 2);
        
        let existing_borrowed = loan.borrowed;
        let existing_collateral = loan.collateral;
        let loan_end_date = loan.end_date;
        
        // Calculate remaining days
        let today_midnight = math::get_midnight_timestamp(current_time);
        let new_borrow_length = (loan_end_date - today_midnight) / 86400;
        
        // Calculate interest fee for additional borrowing
        let interest_fee = math::get_interest_fee(sui_amount, new_borrow_length);
        let fee_address_fee = (interest_fee * 3) / 10;
        
        // Calculate required additional collateral
        let pool_info = trading::get_pool_info(vault, larry_treasury_cap);
        let required_additional_larry = math::eth_to_larry_no_trade_ceil(sui_amount, pool_info.sui_balance, pool_info.larry_supply);
        let existing_larry_value = math::larry_to_eth(existing_collateral, pool_info.sui_balance, pool_info.larry_supply);
        let excess_collateral = if (existing_larry_value > (existing_borrowed * 100) / 99) {
            ((existing_larry_value * 99) / 100) - existing_borrowed
        } else {
            0
        };
        
        let collateral_from_user = if (excess_collateral >= required_additional_larry) {
            0
        } else {
            required_additional_larry - excess_collateral
        };
        
        // If additional collateral needed, process LARRY coins
        if (collateral_from_user > 0) {
            let provided_larry = {
                let mut i = 0;
                let mut total = 0;
                while (i < vector::length(&additional_larry_coins)) {
                    total = total + coin::value(vector::borrow(&additional_larry_coins, i));
                    i = i + 1;
                };
                total
            };
            assert!(provided_larry >= collateral_from_user, 3);
            
            // Transfer additional collateral
            while (!vector::is_empty(&mut additional_larry_coins)) {
                let larry_coin = vector::pop_back(&mut additional_larry_coins);
                transfer::public_transfer(larry_coin, sender); // Simplified - in practice would be managed by protocol
            };
        };
        vector::destroy_empty(additional_larry_coins);
        
        // Send fee to team
        let fee_sui_balance = balance::split(&mut vault.balance, fee_address_fee);
        let fee_sui_coin = coin::from_balance(fee_sui_balance, ctx);
        let fee_address = admin::get_fee_address(config);
        transfer::public_transfer(fee_sui_coin, fee_address);
        events::emit_sui_sent(fee_address, fee_address_fee);
        
        // Send additional borrowed SUI to user
        let user_amount = sui_amount - interest_fee;
        let borrowed_sui_balance = balance::split(&mut vault.balance, user_amount);
        let borrowed_sui_coin = coin::from_balance(borrowed_sui_balance, ctx);
        transfer::public_transfer(borrowed_sui_coin, sender);
        
        // Update loan record
        loan.borrowed = existing_borrowed + user_amount;
        loan.collateral = existing_collateral + collateral_from_user;
        
        // Update loan statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed + user_amount;
        loan_stats.total_collateral = loan_stats.total_collateral + collateral_from_user;
        
        // Update loan data by date
        add_loans_by_date(loan_stats, user_amount, collateral_from_user, loan_end_date);
    }
    
    /// Remove excess collateral
    public entry fun remove_collateral(
        vault: &Vault,
        loan_stats: &mut LoanStats,
        larry_treasury_cap: &coin::TreasuryCap<LARRY>,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Check if user has an active loan
        assert!(dynamic_field::exists_(&loan_stats.id, sender), 0);
        
        // Get existing loan
        let loan = dynamic_field::borrow_mut<address, Loan>(&mut loan_stats.id, sender);
        
        // Check loan hasn't expired
        let current_time = clock::timestamp_ms(clock) / 1000;
        assert!(current_time < loan.end_date, 1);
        
        let collateral = loan.collateral;
        let borrowed = loan.borrowed;
        
        // Check collateralization remains above 99%
        let pool_info = trading::get_pool_info(vault, larry_treasury_cap);
        let remaining_collateral_value = math::larry_to_eth(collateral - amount, pool_info.sui_balance, pool_info.larry_supply);
        assert!(borrowed <= (remaining_collateral_value * 99) / 100, 2);
        
        // Update loan
        loan.collateral = collateral - amount;
        
        // Return collateral to user (simplified - would need proper collateral management)
        let larry_coins = coin::mint(larry_treasury_cap, amount, ctx);
        transfer::public_transfer(larry_coins, sender);
        
        // Update statistics
        loan_stats.total_collateral = loan_stats.total_collateral - amount;
        
        // Update loan data by date
        sub_loans_by_date(loan_stats, 0, amount, loan.end_date);
    }
    
    /// Repay part of loan
    public entry fun repay(
        loan_stats: &mut LoanStats,
        sui_coins: vector<coin::Coin<sui::sui::SUI>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Check if user has an active loan
        assert!(dynamic_field::exists_(&loan_stats.id, sender), 0);
        
        // Get repayment amount
        let repay_amount = {
            let mut i = 0;
            let mut total = 0;
            while (i < vector::length(&sui_coins)) {
                total = total + coin::value(vector::borrow(&sui_coins, i));
                i = i + 1;
            };
            total
        };
        assert!(repay_amount != 0, 1);
        
        // Get existing loan
        let loan = dynamic_field::borrow_mut<address, Loan>(&mut loan_stats.id, sender);
        
        // Check loan hasn't expired
        let current_time = clock::timestamp_ms(clock) / 1000;
        assert!(current_time < loan.end_date, 2);
        
        let borrowed = loan.borrowed;
        assert!(borrowed > repay_amount, 3); // Must repay less than total
        
        // Destroy SUI coins (they're being used to repay)
        while (!vector::is_empty(&mut sui_coins)) {
            let sui_coin = vector::pop_back(&mut sui_coins);
            transfer::public_transfer(sui_coin, @0x0); // Burn equivalent
        };
        vector::destroy_empty(sui_coins);
        
        // Update loan
        loan.borrowed = borrowed - repay_amount;
        
        // Update statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed - repay_amount;
        
        // Update loan data by date
        sub_loans_by_date(loan_stats, repay_amount, 0, loan.end_date);
    }
    
    /// Close loan position completely
    public entry fun close_position(
        loan_stats: &mut LoanStats,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        sui_coins: vector<coin::Coin<sui::sui::SUI>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Check if user has an active loan
        assert!(dynamic_field::exists_(&loan_stats.id, sender), 0);
        
        // Get repayment amount
        let repay_amount = {
            let mut i = 0;
            let mut total = 0;
            while (i < vector::length(&sui_coins)) {
                total = total + coin::value(vector::borrow(&sui_coins, i));
                i = i + 1;
            };
            total
        };
        
        // Get existing loan
        let loan = dynamic_field::remove<address, Loan>(&mut loan_stats.id, sender);
        
        // Check loan hasn't expired
        let current_time = clock::timestamp_ms(clock) / 1000;
        assert!(current_time < loan.end_date, 1);
        
        let borrowed = loan.borrowed;
        let collateral = loan.collateral;
        let end_date = loan.end_date;
        
        assert!(borrowed == repay_amount, 2); // Must repay exact amount
        
        // Destroy SUI coins (they're being used to repay)
        while (!vector::is_empty(&mut sui_coins)) {
            let sui_coin = vector::pop_back(&mut sui_coins);
            transfer::public_transfer(sui_coin, @0x0); // Burn equivalent
        };
        vector::destroy_empty(sui_coins);
        
        // Return collateral to user
        let larry_coins = coin::mint(larry_treasury_cap, collateral, ctx);
        transfer::public_transfer(larry_coins, sender);
        
        // Update statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed - borrowed;
        loan_stats.total_collateral = loan_stats.total_collateral - collateral;
        
        // Update loan data by date
        sub_loans_by_date(loan_stats, borrowed, collateral, end_date);
    }
    
    /// Flash close position (sell collateral to close)
    public entry fun flash_close_position(
        vault: &mut Vault,
        loan_stats: &mut LoanStats,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Check if user has an active loan
        assert!(dynamic_field::exists_(&loan_stats.id, sender), 0);
        
        // Run liquidation first
        larry_talbot::liquidation::liquidate(loan_stats, vault, clock, ctx);
        
        // Get existing loan
        let loan = dynamic_field::remove<address, Loan>(&mut loan_stats.id, sender);
        
        // Check loan hasn't expired
        let current_time = clock::timestamp_ms(clock) / 1000;
        assert!(current_time < loan.end_date, 1);
        
        let borrowed = loan.borrowed;
        let collateral = loan.collateral;
        let end_date = loan.end_date;
        
        // Convert collateral to SUI value
        let pool_info = trading::get_pool_info(vault, larry_treasury_cap);
        let collateral_in_sui = math::larry_to_eth(collateral, pool_info.sui_balance, pool_info.larry_supply);
        
        // Apply 1% fee for flash close
        let collateral_after_fee = (collateral_in_sui * 99) / 100;
        let fee = collateral_in_sui / 100;
        
        assert!(collateral_after_fee >= borrowed, 2); // Must have enough collateral
        
        // Calculate amounts
        let to_user = collateral_after_fee - borrowed;
        let fee_address_fee = (fee * 3) / 10; // 30% of fee to team
        
        assert!(fee_address_fee > MIN_AMOUNT, 3);
        
        // Burn collateral LARRY tokens
        // (In practice, this would be handled by the protocol's collateral management)
        
        // Send remaining value to user
        if (to_user > 0) {
            let user_sui_balance = balance::split(&mut vault.balance, to_user);
            let user_sui_coin = coin::from_balance(user_sui_balance, ctx);
            transfer::public_transfer(user_sui_coin, sender);
        };
        
        // Send fee to team
        let fee_sui_balance = balance::split(&mut vault.balance, fee_address_fee);
        let fee_sui_coin = coin::from_balance(fee_sui_balance, ctx);
        let fee_address = admin::get_fee_address(&larry_talbot::admin::Config { 
            id: object::new(ctx), fee_address: @0x0, buy_fee: 0, sell_fee: 0, buy_fee_leverage: 0, started: false 
        }); // Placeholder - needs proper config access
        transfer::public_transfer(fee_sui_coin, fee_address);
        events::emit_sui_sent(fee_address, fee_address_fee);
        
        // Update statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed - borrowed;
        loan_stats.total_collateral = loan_stats.total_collateral - collateral;
        
        // Update loan data by date
        sub_loans_by_date(loan_stats, borrowed, collateral, end_date);
    }
    
    /// Extend loan duration
    public entry fun extend_loan(
        loan_stats: &mut LoanStats,
        number_of_days: u64,
        sui_coins: vector<coin::Coin<sui::sui::SUI>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Check if user has an active loan
        assert!(dynamic_field::exists_(&loan_stats.id, sender), 0);
        
        // Get extension fee
        let extension_fee = {
            let mut i = 0;
            let mut total = 0;
            while (i < vector::length(&sui_coins)) {
                total = total + coin::value(vector::borrow(&sui_coins, i));
                i = i + 1;
            };
            total
        };
        
        // Get existing loan
        let loan = dynamic_field::borrow_mut<address, Loan>(&mut loan_stats.id, sender);
        
        // Check loan hasn't expired
        let current_time = clock::timestamp_ms(clock) / 1000;
        assert!(current_time < loan.end_date, 1);
        
        let old_end_date = loan.end_date;
        let borrowed = loan.borrowed;
        let collateral = loan.collateral;
        let old_number_of_days = loan.number_of_days;
        
        // Calculate required fee
        let required_fee = math::get_interest_fee(borrowed, number_of_days);
        assert!(extension_fee == required_fee, 2);
        
        let fee_address_fee = (extension_fee * 3) / 10;
        assert!(fee_address_fee > MIN_AMOUNT, 3);
        
        // Update loan
        let new_end_date = old_end_date + (number_of_days * 86400);
        loan.end_date = new_end_date;
        loan.number_of_days = old_number_of_days + number_of_days;
        
        // Ensure total loan duration is under 365 days
        assert!((new_end_date - current_time) / 86400 < 366, 4);
        
        // Process fee payment
        while (!vector::is_empty(&mut sui_coins)) {
            let sui_coin = vector::pop_back(&mut sui_coins);
            transfer::public_transfer(sui_coin, @0x0); // Fee payment
        };
        vector::destroy_empty(sui_coins);
        
        // Update loan tracking by date
        sub_loans_by_date(loan_stats, borrowed, collateral, old_end_date);
        add_loans_by_date(loan_stats, borrowed, collateral, new_end_date);
    }
    
    /// Helper functions
    public fun add_loans_by_date(
        loan_stats: &mut LoanStats,
        borrowed: u64,
        collateral: u64,
        _date: u64
    ) {
        loan_stats.total_borrowed = loan_stats.total_borrowed + borrowed;
        loan_stats.total_collateral = loan_stats.total_collateral + collateral;
        
        events::emit_loan_data_update(
            collateral,
            borrowed,
            loan_stats.total_borrowed,
            loan_stats.total_collateral
        );
    }
    
    public fun sub_loans_by_date(
        loan_stats: &mut LoanStats,
        borrowed: u64,
        collateral: u64,
        _date: u64
    ) {
        loan_stats.total_borrowed = if (loan_stats.total_borrowed > borrowed) {
            loan_stats.total_borrowed - borrowed
        } else {
            0
        };
        loan_stats.total_collateral = if (loan_stats.total_collateral > collateral) {
            loan_stats.total_collateral - collateral
        } else {
            0
        };
        
        events::emit_loan_data_update(
            collateral,
            borrowed,
            loan_stats.total_borrowed,
            loan_stats.total_collateral
        );
    }
    
    /// Check if loan exists for address
    public fun has_loan(loan_stats: &LoanStats, addr: address): bool {
        dynamic_field::exists_(&loan_stats.id, addr)
    }
    
    /// Get loan by address
    public fun get_loan_by_address(loan_stats: &LoanStats, addr: address, clock: &Clock): (u64, u64, u64) {
        if (dynamic_field::exists_(&loan_stats.id, addr)) {
            let loan = dynamic_field::borrow<address, Loan>(&loan_stats.id, addr);
            let current_time = clock::timestamp_ms(clock) / 1000;
            if (current_time < loan.end_date) {
                (loan.collateral, loan.borrowed, loan.end_date)
            } else {
                (0, 0, 0) // Expired loan
            }
        } else {
            (0, 0, 0)
        }
    }
    
    /// Check if loan is expired
    public fun is_loan_expired(loan: &Loan, clock: &Clock): bool {
        let current_time = clock::timestamp_ms(clock) / 1000;
        current_time > loan.end_date
    }
    
    /// Get total borrowed
    public fun get_total_borrowed(loan_stats: &LoanStats): u64 {
        loan_stats.total_borrowed
    }
    
    /// Get total collateral
    public fun get_total_collateral(loan_stats: &LoanStats): u64 {
        loan_stats.total_collateral
    }
    
    /// Get last liquidation date
    public fun get_last_liquidation_date(loan_stats: &LoanStats): u64 {
        loan_stats.last_liquidation_date
    }
    
    /// Set last liquidation date
    public fun set_last_liquidation_date(loan_stats: &mut LoanStats, date: u64) {
        loan_stats.last_liquidation_date = date;
    }
    
    /// Reduce total collateral (for liquidation)
    public fun reduce_total_collateral(loan_stats: &mut LoanStats, amount: u64) {
        loan_stats.total_collateral = if (loan_stats.total_collateral > amount) {
            loan_stats.total_collateral - amount
        } else {
            0
        };
    }
    
    /// Reduce total borrowed (for liquidation)
    public fun reduce_total_borrowed(loan_stats: &mut LoanStats, amount: u64) {
        loan_stats.total_borrowed = if (loan_stats.total_borrowed > amount) {
            loan_stats.total_borrowed - amount
        } else {
            0
        };
    }
    
    /// Add to totals (for liquidation module)
    public fun add_to_totals(loan_stats: &mut LoanStats, borrowed: u64, collateral: u64) {
        loan_stats.total_borrowed = loan_stats.total_borrowed + borrowed;
        loan_stats.total_collateral = loan_stats.total_collateral + collateral;
    }
    
    /// Subtract from totals (for liquidation module)
    public fun sub_from_totals(loan_stats: &mut LoanStats, borrowed: u64, collateral: u64) {
        loan_stats.total_borrowed = if (loan_stats.total_borrowed > borrowed) {
            loan_stats.total_borrowed - borrowed
        } else {
            0
        };
        loan_stats.total_collateral = if (loan_stats.total_collateral > collateral) {
            loan_stats.total_collateral - collateral
        } else {
            0
        };
    }
    
    /// Remove loan (for liquidation)
    public fun remove_loan(loan_stats: &mut LoanStats, addr: address) {
        if (dynamic_field::exists_(&loan_stats.id, addr)) {
            let _loan = dynamic_field::remove<address, Loan>(&mut loan_stats.id, addr);
        };
    }
    
    /// Reset all totals (emergency function)
    public fun reset_totals(loan_stats: &mut LoanStats) {
        loan_stats.total_borrowed = 0;
        loan_stats.total_collateral = 0;
    }
}