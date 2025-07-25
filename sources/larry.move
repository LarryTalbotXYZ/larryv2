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
    public fun init(
        witness: larry_token::LARRY,
        ctx: &mut TxContext
    ) {
        // Initialize LARRY token
        let (treasury_cap, metadata) = coin::create_currency(
            witness, 
            9, // 9 decimals like SUI
            b"LARRY TALBOT",
            b"LARRY",
            b"LARRY TALBOT Token",
            option::none(),
            ctx
        );
        
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
        // Validate fee address is set
        assert!(admin::get_fee_address(&protocol.config) != @0x0, 0);
        
        // Check exactly 0.001 SUI is sent (equivalent to 0.001 ETH)
        let total_sui = {
            let mut total = 0;
            let mut i = 0;
            while (i < vector::length(&sui_coins)) {
                total = total + coin::value(vector::borrow(&sui_coins, i));
                i = i + 1;
            };
            total
        };
        assert!(total_sui == 1_000_000, 1); // 0.001 SUI with 9 decimals
        
        // Mint 1000 LARRY tokens for team
        let team_amount = 1_000_000_000_000; // 1000 LARRY with 9 decimals
        let team_coins = coin::mint(&mut protocol_caps.larry_treasury_cap, team_amount, ctx);
        
        // Burn 1% of minted tokens (10 LARRY)
        let burn_amount = team_amount / 100;
        let burn_coin = coin::split(&mut team_coins, burn_amount, ctx);
        coin::burn(&mut protocol_caps.larry_treasury_cap, burn_coin);
        
        // Transfer remaining to sender
        transfer::public_transfer(team_coins, tx_context::sender(ctx));
        
        // Start the protocol
        admin::set_start(&protocol_caps.admin_cap, &mut protocol.config);
        
        // Add SUI to vault
        while (!vector::is_empty(&mut sui_coins)) {
            let sui_coin = vector::pop_back(&mut sui_coins);
            let sui_balance = coin::into_balance(sui_coin);
            balance::join(&mut protocol.vault.balance, sui_balance);
        };
        vector::destroy_empty(sui_coins);
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
    
    /// Safety check to ensure price doesn't decrease
    public fun safety_check(
        protocol: &Protocol,
        new_sui_amount: u64
    ): bool {
        let new_backing = get_backing(protocol) + new_sui_amount;
        let larry_supply = coin::total_supply(&protocol_caps.larry_treasury_cap);
        
        if (larry_supply == 0) {
            return true
        };
        
        let new_price = (new_backing * 1_000_000_000) / larry_supply; // Price with 9 decimals
        // In a real implementation, we would compare with last price
        // For this example, we'll just return true
        true
    }
}
