// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::math {
    
    /// Convert SUI to LARRY tokens
    public fun eth_to_larry(value: u64, backing: u64, supply: u64): u64 {
        if (supply == 0 || backing == 0) {
            return value * 1000000000; // Default 1:1 with 9 decimals
        };
        
        // Calculate: (value * supply) / (backing - value)
        // But avoid division by zero
        if (backing <= value) {
            return 0;
        };
        
        (value * supply) / (backing - value)
    }
    
    /// Convert LARRY tokens to SUI
    public fun larry_to_eth(value: u64, backing: u64, supply: u64): u64 {
        if (supply == 0) {
            return 0;
        };
        
        (value * backing) / supply
    }
    
    /// Convert SUI to LARRY without trade (for calculations)
    public fun eth_to_larry_no_trade(value: u64, backing: u64, supply: u64): u64 {
        if (supply == 0 || backing == 0) {
            return value * 1000000000; // Default 1:1 with 9 decimals
        };
        
        (value * supply) / backing
    }
    
    /// Convert SUI to LARRY with leverage
    public fun eth_to_larry_leverage(value: u64, fee: u64, backing: u64, supply: u64): u64 {
        if (supply == 0) {
            return value * 1000000000; // Default 1:1 with 9 decimals
        };
        
        let adjusted_backing = if (backing > fee) { backing - fee } else { 1 };
        if (adjusted_backing == 0) {
            return value * 1000000000;
        };
        
        // Calculate: (value * supply + (adjusted_backing - 1)) / adjusted_backing
        let numerator = (value * supply) + (adjusted_backing - 1);
        numerator / adjusted_backing
    }
    
    /// Calculate interest fee
    public fun get_interest_fee(amount: u64, number_of_days: u64): u64 {
        // Interest rate: 3.9% + 0.1% base per year
        // For simplicity: (0.039 * number_of_days / 365) + 0.001
        let interest_rate_basis_points = (390 * number_of_days) / 365 + 10; // 390 = 3.9% in basis points
        (amount * interest_rate_basis_points) / 10000
    }
    
    /// Convert SUI to LARRY with ceiling (round up)
    public fun eth_to_larry_no_trade_ceil(value: u64, backing: u64, supply: u64): u64 {
        if (supply == 0 || backing == 0) {
            return value * 1000000000; // Default 1:1 with 9 decimals
        };
        
        // Calculate: (value * supply + (backing - 1)) / backing
        let numerator = (value * supply) + (backing - 1);
        numerator / backing
    }
    
    /// Get midnight timestamp
    public fun get_midnight_timestamp(timestamp: u64): u64 {
        let seconds_in_day = 86400;
        let midnight_timestamp = timestamp - (timestamp % seconds_in_day);
        midnight_timestamp + seconds_in_day
    }
}
