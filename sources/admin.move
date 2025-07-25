// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::admin {
    use sui::object;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::event;
    
    /// Admin capability for controlling protocol parameters
    struct AdminCap has key, store {
        id: object::UID
    }
    
    /// Protocol configuration parameters
    struct Config has key {
        id: object::UID,
        fee_address: address,
        buy_fee: u16,       // Fee in basis points (10000 = 100%)
        sell_fee: u16,      // Fee in basis points
        buy_fee_leverage: u16, // Leverage fee in basis points
        started: bool
    }
    
    /// Event for updating fee address
    struct FeeAddressUpdated has copy, drop {
        new_address: address
    }
    
    /// Event for updating buy fee
    struct BuyFeeUpdated has copy, drop {
        new_fee: u16
    }
    
    /// Event for updating sell fee
    struct SellFeeUpdated has copy, drop {
        new_fee: u16
    }
    
    /// Event for updating leverage fee
    struct LeverageFeeUpdated has copy, drop {
        new_fee: u16
    }
    
    /// Event for protocol start
    struct ProtocolStarted has copy, drop {
        started: bool
    }
    
    /// Constants for fee validation
    const MIN_BUY_FEE: u16 = 9975;  // 0.25% max fee
    const MAX_BUY_FEE: u16 = 9996;  // 0.04% min fee
    const MIN_SELL_FEE: u16 = 9975; // 0.25% max fee
    const MAX_SELL_FEE: u16 = 9996; // 0.04% min fee
    const MAX_LEVERAGE_FEE: u16 = 250; // 2.5% max leverage fee
    
    /// Create the admin capability and initial config
    public fun create_admin(ctx: &mut TxContext): (AdminCap, Config) {
        let admin_cap = AdminCap {
            id: object::new(ctx)
        };
        
        let config = Config {
            id: object::new(ctx),
            fee_address: tx_context::sender(ctx), // Default to deployer
            buy_fee: 9990,    // 0.1% fee
            sell_fee: 9990,   // 0.1% fee
            buy_fee_leverage: 100, // 1% leverage fee
            started: false
        };
        
        (admin_cap, config)
    }
    
    /// Transfer admin capability to another address
    public entry fun transfer_admin(admin_cap: AdminCap, to: address, _ctx: &mut TxContext) {
        transfer::public_transfer(admin_cap, to);
    }
    
    /// Set the fee address
    public entry fun set_fee_address(
        _admin_cap: &AdminCap,
        config: &mut Config,
        new_address: address
    ) {
        assert!(new_address != @0x0, 0); // Cannot set to zero address
        config.fee_address = new_address;
        event::emit(FeeAddressUpdated { new_address });
    }
    
    /// Set the buy fee
    public entry fun set_buy_fee(
        _admin_cap: &AdminCap,
        config: &mut Config,
        amount: u16
    ) {
        assert!(amount <= MAX_BUY_FEE, 1); // Must be less than 0.25%
        assert!(amount >= MIN_BUY_FEE, 2); // Must be greater than 0.04%
        config.buy_fee = amount;
        event::emit(BuyFeeUpdated { new_fee: amount });
    }
    
    /// Set the sell fee
    public entry fun set_sell_fee(
        _admin_cap: &AdminCap,
        config: &mut Config,
        amount: u16
    ) {
        assert!(amount <= MAX_SELL_FEE, 3); // Must be less than 0.25%
        assert!(amount >= MIN_SELL_FEE, 4); // Must be greater than 0.04%
        config.sell_fee = amount;
        event::emit(SellFeeUpdated { new_fee: amount });
    }
    
    /// Set the leverage buy fee
    public entry fun set_buy_fee_leverage(
        _admin_cap: &AdminCap,
        config: &mut Config,
        amount: u16
    ) {
        assert!(amount <= MAX_LEVERAGE_FEE, 5); // Must be less than 2.5%
        assert!(amount >= 0, 6); // Must be greater than 0%
        config.buy_fee_leverage = amount;
        event::emit(LeverageFeeUpdated { new_fee: amount });
    }
    
    /// Start the protocol
    public entry fun set_start(
        _admin_cap: &AdminCap,
        config: &mut Config
    ) {
        config.started = true;
        event::emit(ProtocolStarted { started: true });
    }
    
    /// Getters for config values
    public fun get_fee_address(config: &Config): address {
        config.fee_address
    }
    
    public fun get_buy_fee(config: &Config): u16 {
        config.buy_fee
    }
    
    public fun get_sell_fee(config: &Config): u16 {
        config.sell_fee
    }
    
    public fun get_buy_fee_leverage(config: &Config): u16 {
        config.buy_fee_leverage
    }
    
    public fun is_started(config: &Config): bool {
        config.started
    }
}
