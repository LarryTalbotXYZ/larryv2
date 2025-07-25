// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::events {
    use sui::event;
    
    /// Event for price updates
    struct PriceUpdated has copy, drop {
        timestamp: u64,
        price: u64,
        volume_in_sui: u64
    }
    
    /// Event for liquidation
    struct Liquidation has copy, drop {
        timestamp: u64,
        amount: u64
    }
    
    /// Event for loan data updates
    struct LoanDataUpdated has copy, drop {
        collateral_by_date: u64,
        borrowed_by_date: u64,
        total_borrowed: u64,
        total_collateral: u64
    }
    
    /// Event for sending SUI
    struct SUI_Sent has copy, drop {
        to: address,
        amount: u64
    }
    
    /// Event for max supply updates
    struct MaxSupplyUpdated has copy, drop {
        new_max: u64
    }
    
    /// Emit price update event
    public fun emit_price_update(timestamp: u64, price: u64, volume_in_sui: u64) {
        event::emit(PriceUpdated {
            timestamp,
            price,
            volume_in_sui
        })
    }
    
    /// Emit liquidation event
    public fun emit_liquidation(timestamp: u64, amount: u64) {
        event::emit(Liquidation {
            timestamp,
            amount
        })
    }
    
    /// Emit loan data update event
    public fun emit_loan_data_update(
        collateral_by_date: u64,
        borrowed_by_date: u64,
        total_borrowed: u64,
        total_collateral: u64
    ) {
        event::emit(LoanDataUpdated {
            collateral_by_date,
            borrowed_by_date,
            total_borrowed,
            total_collateral
        })
    }
    
    /// Emit SUI sent event
    public fun emit_sui_sent(to: address, amount: u64) {
        event::emit(SUI_Sent {
            to,
            amount
        })
    }
    
    /// Emit max supply update event
    public fun emit_max_supply_updated(new_max: u64) {
        event::emit(MaxSupplyUpdated {
            new_max
        })
    }
}
