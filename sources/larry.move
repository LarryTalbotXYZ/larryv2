// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::larry {
    use std::option;
    use sui::balance;
    use sui::coin;
    use sui::object;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field;
    use sui::clock::Clock;
    use std::vector;
    use larry_talbot::larry_token::{Self, LARRY};
    use larry_talbot::admin::{Self, Config, AdminCap};
    use larry_talbot::events;
    use larry_talbot::math;
    use larry_talbot::trading::{Self, Vault};
    use larry_talbot::lending::{Self, Loan, LoanStats, Collateral};
    use larry_talbot::liquidation;
    
    /// Main protocol state
    struct Protocol has key {
        id: object::UID,
        vault: Vault,
        config: Config,
        loan_stats: LoanStats
    }
    
    /// Protocol capabilities
    struct ProtocolCaps has key {
        id: object::UID,
        admin_cap: AdminCap,
        larry_treasury_cap: coin::TreasuryCap<LARRY>
    }
    
    /// Initialize the entire protocol
    fun init(ctx: &mut TxContext) {
        // Create LARRY witness and initialize token
        let larry_witness = larry_token::LARRY {};
        let (treasury_cap, metadata) = larry_token::create_currency(larry_witness, ctx);
        
        // Create admin capabilities
        let (admin_cap, config) = admin::create_admin(ctx);
        
        // Create trading vault
        let vault = trading::create_vault(ctx);
        
        // Create loan statistics
        let loan_stats = lending::create_loan_stats(ctx);
        
        // Create protocol state
        let protocol = Protocol {
            id: object::new(ctx),
            vault,
            config,
            loan_stats
        };
        
        // Create protocol capabilities
        let protocol_caps = ProtocolCaps {
            id: object::new(ctx),
            admin_cap,
            larry_treasury_cap: treasury_cap
        };
        
        // Transfer objects to deployer
        transfer::public_transfer(protocol, tx_context::sender(ctx));
        transfer::public_transfer(protocol_caps, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
    }
    
    /// Team start function (equivalent to setStart in EVM version)
    public entry fun team_start(
        protocol: &mut Protocol,
        protocol_caps: &mut ProtocolCaps,
        sui_coins: vector<coin::Coin<sui::sui::SUI>>,
        ctx: &mut TxContext
    ) {
        // Only admin can call this function
        assert!(!admin::is_started(&protocol.config), 0);
        
        // Validate fee address is set
        assert!(admin::get_fee_address(&protocol.config) != @0x0, 1);
        
        // Check exactly 0.001 SUI is sent (equivalent to 0.001 ETH in original)
        let total_sui = {
            let mut total = 0;
            let mut i = 0;
            while (i < vector::length(&sui_coins)) {
                total = total + coin::value(vector::borrow(&sui_coins, i));
                i = i + 1;
            };
            total
        };
        assert!(total_sui == 1_000_000, 2); // 0.001 SUI with 9 decimals
        
        // Mint initial team tokens (matching EVM contract)
        let team_amount = 1_000_000_000_000; // 1000 LARRY with 9 decimals
        let mut team_coins = coin::mint(&mut protocol_caps.larry_treasury_cap, team_amount, ctx);
        
        // Burn 1% of minted tokens (10 LARRY) - matching EVM behavior
        let burn_amount = team_amount / 100;
        let burn_coin = coin::split(&mut team_coins, burn_amount, ctx);
        coin::burn(&mut protocol_caps.larry_treasury_cap, burn_coin);
        
        // Send remaining 990 LARRY to team/deployer
        transfer::public_transfer(team_coins, tx_context::sender(ctx));
        
        // Add initial SUI liquidity to vault
        while (!vector::is_empty(&mut sui_coins)) {
            let sui_coin = vector::pop_back(&mut sui_coins);
            let sui_balance = coin::into_balance(sui_coin);
            balance::join(&mut protocol.vault.balance, sui_balance);
        };
        vector::destroy_empty(sui_coins);
        
        // Start the protocol (enables trading)
        admin::set_start(&protocol_caps.admin_cap, &mut protocol.config);
        
        // Emit protocol started event
        events::emit_protocol_started(
            tx_context::sender(ctx),
            team_amount - burn_amount, // Net team tokens
            total_sui // Initial SUI backing
        );
    }
    
    /// Get protocol backing (SUI balance + total borrowed)
    public fun get_backing(protocol: &Protocol): u64 {
        let vault_balance = balance::value(&protocol.vault.balance);
        let total_borrowed = protocol.loan_stats.total_borrowed;
        vault_balance + total_borrowed
    }
    
    /// Get total borrowed
    public fun get_total_borrowed(protocol: &Protocol): u64 {
        protocol.loan_stats.total_borrowed
    }
    
    /// Get total collateral
    public fun get_total_collateral(protocol: &Protocol): u64 {
        protocol.loan_stats.total_collateral
    }
    
    /// Safety check to ensure price doesn't decrease - simplified version
    public fun safety_check(
        _protocol: &Protocol,
        _new_sui_amount: u64
    ): bool {
        // For this simplified version, we'll just return true
        // In a real implementation, this would check price consistency
        true
    }
}
