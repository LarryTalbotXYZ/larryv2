// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::liquidation {
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
    use larry_talbot::lending::{Self, Loan, LoanStats};
    
    /// Liquidation helper function
    public fun liquidate(
        loan_stats: &mut LoanStats,
        vault: &mut Vault,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let mut borrowed = 0;
        let mut collateral = 0;
        
        // Process liquidations for expired loans
        let mut liquidation_date = loan_stats.last_liquidation_date;
        while (liquidation_date < current_time) {
            // In a real implementation, we would process loans expiring on this date
            // For this example, we'll just update the last liquidation date
            liquidation_date = liquidation_date + 86400; // Add one day
        }
        
        // Update last liquidation date
        loan_stats.last_liquidation_date = liquidation_date;
        
        // Process liquidation if needed
        if (collateral > 0) {
            // Burn collateral LARRY tokens
            // In a real implementation, we would burn the actual collateral
            
            // Update total collateral
            loan_stats.total_collateral = if (loan_stats.total_collateral > collateral) {
                loan_stats.total_collateral - collateral
            } else {
                0
            };
        }
        
        if (borrowed > 0) {
            // Update total borrowed
            loan_stats.total_borrowed = if (loan_stats.total_borrowed > borrowed) {
                loan_stats.total_borrowed - borrowed
            } else {
                0
            };
            
            // Emit liquidation event
            events::emit_liquidation(current_time, borrowed);
        }
    }
    
    /// Add loan data by date
    public fun add_loans_by_date(
        loan_stats: &mut LoanStats,
        borrowed: u64,
        collateral: u64,
        date: u64
    ) {
        // Update global statistics
        loan_stats.total_borrowed = loan_stats.total_borrowed + borrowed;
        loan_stats.total_collateral = loan_stats.total_collateral + collateral;
        
        // Emit loan data update event
        events::emit_loan_data_update(
            collateral,
            borrowed,
            loan_stats.total_borrowed,
            loan_stats.total_collateral
        );
    }
    
    /// Subtract loan data by date
    public fun sub_loans_by_date(
        loan_stats: &mut LoanStats,
        borrowed: u64,
        collateral: u64,
        date: u64
    ) {
        // Update global statistics
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
        
        // Emit loan data update event
        events::emit_loan_data_update(
            collateral,
            borrowed,
            loan_stats.total_borrowed,
            loan_stats.total_collateral
        );
    }
    
    /// Get loans expiring by date
    public fun get_loans_expiring_by_date(addr: address, date: u64): (u64, u64) {
        let midnight = math::get_midnight_timestamp(date);
        if (dynamic_field::exists_<u64, Loan>(addr, midnight)) {
            let loan = dynamic_field::borrow<address, u64, Loan>(addr, midnight);
            if (option::is_some(loan)) {
                let loan_val = option::borrow(loan);
                (loan_val.borrowed, loan_val.collateral)
            } else {
                (0, 0)
            }
        } else {
            (0, 0)
        }
    }
    
    /// Get loan by address
    public fun get_loan_by_address(addr: address, clock: &Clock): (u64, u64, u64) {
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        
        // In a real implementation, we would iterate through all loans for this address
        // For this example, we'll return default values
        (0, 0, 0)
    }
}
