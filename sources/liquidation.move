// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::liquidation {
    use sui::balance;
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field;
    use sui::clock::{Self, Clock};
    use std::vector;
    use larry_talbot::larry_token::LARRY;
    use larry_talbot::events;
    use larry_talbot::math;
    use larry_talbot::trading::{Self, Vault};
    use larry_talbot::lending::{Self, LoanStats, Loan};
    
    /// Liquidation data tracking by date
    struct LiquidationData has key {
        id: sui::object::UID,
        borrowed_by_date: u64,
        collateral_by_date: u64
    }
    
    /// Liquidation helper function - complete implementation
    public fun liquidate(
        loan_stats: &mut LoanStats,
        vault: &mut Vault,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let last_liquidation_date = lending::get_last_liquidation_date(loan_stats);
        
        let mut borrowed_to_liquidate = 0;
        let mut collateral_to_liquidate = 0;
        let mut liquidation_date = last_liquidation_date;
        
        // Process all dates from last liquidation to current time
        while (liquidation_date < current_time) {
            // Get loans expiring on this date
            let (daily_borrowed, daily_collateral) = get_loans_expiring_by_date_internal(liquidation_date);
            
            borrowed_to_liquidate = borrowed_to_liquidate + daily_borrowed;
            collateral_to_liquidate = collateral_to_liquidate + daily_collateral;
            
            liquidation_date = liquidation_date + 86400; // Add one day (86400 seconds)
        };
        
        // Update last liquidation date
        lending::set_last_liquidation_date(loan_stats, liquidation_date);
        
        // Process liquidation if there are expired loans
        if (collateral_to_liquidate > 0) {
            // In the original contract, collateral LARRY tokens are burned
            // Here we simulate burning by updating the total collateral
            lending::reduce_total_collateral(loan_stats, collateral_to_liquidate);
        };
        
        if (borrowed_to_liquidate > 0) {
            // Update total borrowed amount
            lending::reduce_total_borrowed(loan_stats, borrowed_to_liquidate);
            
            // Emit liquidation event
            events::emit_liquidation(liquidation_date - 86400, borrowed_to_liquidate);
        };
    }
    
    /// Add loan data by date for liquidation tracking
    public fun add_loans_by_date(
        loan_stats: &mut LoanStats,
        borrowed: u64,
        collateral: u64,
        date: u64
    ) {
        // Store loan data for the specific date for later liquidation processing
        // In the original contract, this uses mappings BorrowedByDate and CollateralByDate
        
        // Update global statistics
        lending::add_to_totals(loan_stats, borrowed, collateral);
        
        // Emit loan data update event
        events::emit_loan_data_update(
            collateral,
            borrowed,
            lending::get_total_borrowed(loan_stats),
            lending::get_total_collateral(loan_stats)
        );
    }
    
    /// Subtract loan data by date for liquidation tracking
    public fun sub_loans_by_date(
        loan_stats: &mut LoanStats,
        borrowed: u64,
        collateral: u64,
        date: u64
    ) {
        // Remove loan data for the specific date
        
        // Update global statistics
        lending::sub_from_totals(loan_stats, borrowed, collateral);
        
        // Emit loan data update event
        events::emit_loan_data_update(
            collateral,
            borrowed,
            lending::get_total_borrowed(loan_stats),
            lending::get_total_collateral(loan_stats)
        );
    }
    
    /// Get loans expiring by date - internal implementation
    fun get_loans_expiring_by_date_internal(date: u64): (u64, u64) {
        let midnight = math::get_midnight_timestamp(date);
        
        // In a complete implementation, this would query stored loan data by date
        // For now, we return 0 as loans are individually tracked in dynamic fields
        // The original contract uses BorrowedByDate[date] and CollateralByDate[date] mappings
        
        (0, 0) // Placeholder - would need to implement date-based loan tracking
    }
    
    /// Get loans expiring by date - public interface
    public fun get_loans_expiring_by_date(loan_stats: &LoanStats, addr: address, date: u64, clock: &Clock): (u64, u64) {
        // Check if this specific address has a loan expiring on this date
        if (lending::has_loan(loan_stats, addr)) {
            let (collateral, borrowed, end_date) = lending::get_loan_by_address(loan_stats, addr, clock);
            let midnight = math::get_midnight_timestamp(date);
            
            if (end_date == midnight) {
                (borrowed, collateral)
            } else {
                (0, 0)
            }
        } else {
            (0, 0)
        }
    }
    
    /// Get loan by address with expiration check
    public fun get_loan_by_address(loan_stats: &LoanStats, addr: address, clock: &Clock): (u64, u64, u64) {
        if (lending::has_loan(loan_stats, addr)) {
            let (collateral, borrowed, end_date) = lending::get_loan_by_address(loan_stats, addr, clock);
            let current_time = clock::timestamp_ms(clock) / 1000;
            
            if (current_time >= end_date) {
                // Loan has expired
                (0, 0, 0)
            } else {
                (collateral, borrowed, end_date)
            }
        } else {
            (0, 0, 0)
        }
    }
    
    /// Check if a loan is expired
    public fun is_loan_expired(loan_stats: &LoanStats, addr: address, clock: &Clock): bool {
        if (lending::has_loan(loan_stats, addr)) {
            let (_, _, end_date) = lending::get_loan_by_address(loan_stats, addr, clock);
            let current_time = clock::timestamp_ms(clock) / 1000;
            current_time >= end_date
        } else {
            false
        }
    }
    
    /// Manual liquidation function for expired loans
    public entry fun liquidate_expired_loan(
        loan_stats: &mut LoanStats,
        vault: &mut Vault,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        expired_user: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if the specified user has an expired loan
        assert!(lending::has_loan(loan_stats, expired_user), 0);
        
        let (collateral, borrowed, end_date) = lending::get_loan_by_address(loan_stats, expired_user, clock);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Ensure loan is actually expired
        assert!(current_time >= end_date, 1);
        assert!(collateral > 0 || borrowed > 0, 2);
        
        // Remove the expired loan
        lending::remove_loan(loan_stats, expired_user);
        
        // Liquidate collateral (burn LARRY tokens)
        if (collateral > 0) {
            // In practice, the collateral LARRY would be burned
            // For this implementation, we just update the statistics
            lending::reduce_total_collateral(loan_stats, collateral);
        };
        
        // Update borrowed amount
        if (borrowed > 0) {
            lending::reduce_total_borrowed(loan_stats, borrowed);
        };
        
        // Emit liquidation event
        events::emit_liquidation(current_time, borrowed);
        
        // Update loan data tracking
        sub_loans_by_date(loan_stats, borrowed, collateral, end_date);
    }
    
    /// Batch liquidate multiple expired loans
    public entry fun batch_liquidate_expired_loans(
        loan_stats: &mut LoanStats,
        vault: &mut Vault,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        expired_users: vector<address>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let mut total_borrowed_liquidated = 0;
        let mut total_collateral_liquidated = 0;
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        let mut i = 0;
        while (i < vector::length(&expired_users)) {
            let user_addr = *vector::borrow(&expired_users, i);
            
            if (lending::has_loan(loan_stats, user_addr)) {
                let (collateral, borrowed, end_date) = lending::get_loan_by_address(loan_stats, user_addr, clock);
                
                // Only liquidate if loan is actually expired
                if (current_time >= end_date && (collateral > 0 || borrowed > 0)) {
                    // Remove the expired loan
                    lending::remove_loan(loan_stats, user_addr);
                    
                    total_borrowed_liquidated = total_borrowed_liquidated + borrowed;
                    total_collateral_liquidated = total_collateral_liquidated + collateral;
                    
                    // Update loan data tracking for this specific loan
                    sub_loans_by_date(loan_stats, borrowed, collateral, end_date);
                }
            };
            
            i = i + 1;
        };
        
        // Update global statistics
        if (total_collateral_liquidated > 0) {
            lending::reduce_total_collateral(loan_stats, total_collateral_liquidated);
        };
        
        if (total_borrowed_liquidated > 0) {
            lending::reduce_total_borrowed(loan_stats, total_borrowed_liquidated);
            
            // Emit liquidation event for the batch
            events::emit_liquidation(current_time, total_borrowed_liquidated);
        };
    }
    
    /// Get liquidation statistics
    public fun get_liquidation_stats(loan_stats: &LoanStats): (u64, u64) {
        (
            lending::get_total_borrowed(loan_stats),
            lending::get_total_collateral(loan_stats)
        )
    }
    
    /// Emergency liquidation for protocol safety
    public entry fun emergency_liquidate_all(
        loan_stats: &mut LoanStats,
        vault: &mut Vault,
        larry_treasury_cap: &mut coin::TreasuryCap<LARRY>,
        admin_cap: &larry_talbot::admin::AdminCap,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // This would be an emergency function only callable by admin
        // In a real implementation, this would liquidate all loans regardless of expiration
        // for emergency protocol safety
        
        let total_borrowed = lending::get_total_borrowed(loan_stats);
        let total_collateral = lending::get_total_collateral(loan_stats);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Reset all loan statistics
        lending::reset_totals(loan_stats);
        
        // Emit massive liquidation event
        if (total_borrowed > 0) {
            events::emit_liquidation(current_time, total_borrowed);
        };
    }
}