// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module larry_talbot::larry_test {
    use std::signer;
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use larry_talbot::larry_token::{Self, LARRY};
    use larry_talbot::admin::{Self, Config};
    use larry_talbot::trading::{Self, Vault};
    use larry_talbot::lending::{Self, LoanStats};
    use larry_talbot::larry::{Self, Protocol, ProtocolCaps};
    
    #[test]
    fun test_protocol_initialization() {
        let scenario = Scenario::new();
        let admin = scenario.address(0);
        let admin_signer = scenario.account(0);
        
        scenario.next_tx(admin, vector[]);
        
        // Initialize the protocol
        let larry_witness = LARRY {};
        larry::init(larry_witness, &mut scenario.ctx());
        
        // Verify protocol objects were created
        scenario.take::<Protocol>(admin);
        scenario.take::<ProtocolCaps>(admin);
    }
    
    #[test]
    fun test_token_minting() {
        let scenario = Scenario::new();
        let admin = scenario.address(0);
        let user = scenario.address(1);
        let admin_signer = scenario.account(0);
        
        scenario.next_tx(admin, vector[]);
        
        // Initialize the protocol
        let larry_witness = LARRY {};
        larry::init(larry_witness, &mut scenario.ctx());
        
        let mut protocol = scenario.take::<Protocol>(admin);
        let mut protocol_caps = scenario.take::<ProtocolCaps>(admin);
        
        scenario.next_tx(admin, vector[]);
        
        // Test team start function
        let sui_coins = coin::mint_for_testing(1_000_000, &mut scenario.ctx()); // 0.001 SUI
        larry::team_start(&mut protocol, &mut protocol_caps, sui_coins, &mut scenario.ctx());
        
        // Verify protocol is started
        assert!(admin::is_started(&protocol.config), 0);
        
        scenario.restore(protocol);
        scenario.restore(protocol_caps);
    }
    
    #[test]
    fun test_admin_functions() {
        let scenario = Scenario::new();
        let admin = scenario.address(0);
        let new_fee_address = scenario.address(1);
        let admin_signer = scenario.account(0);
        
        scenario.next_tx(admin, vector[]);
        
        // Create admin capability and config
        let (admin_cap, mut config) = admin::create_admin(&mut scenario.ctx());
        
        // Test setting fee address
        admin::set_fee_address(&admin_cap, &mut config, new_fee_address);
        assert!(admin::get_fee_address(&config) == new_fee_address, 1);
        
        // Test setting buy fee
        admin::set_buy_fee(&admin_cap, &mut config, 9980); // 0.2% fee
        assert!(admin::get_buy_fee(&config) == 9980, 2);
        
        // Test setting sell fee
        admin::set_sell_fee(&admin_cap, &mut config, 9985); // 0.15% fee
        assert!(admin::get_sell_fee(&config) == 9985, 3);
        
        // Test setting leverage fee
        admin::set_buy_fee_leverage(&admin_cap, &mut config, 150); // 1.5% fee
        assert!(admin::get_buy_fee_leverage(&config) == 150, 4);
    }
    
    #[test]
    fun test_math_functions() {
        use larry_talbot::math::{Self};
        
        // Test ETH to LARRY conversion
        let larry_amount = math::eth_to_larry(1_000_000_000, 10_000_000_000, 1_000_000_000_000);
        assert!(larry_amount > 0, 0);
        
        // Test LARRY to ETH conversion
        let eth_amount = math::larry_to_eth(1_000_000_000, 10_000_000_000, 1_000_000_000_000);
        assert!(eth_amount > 0, 1);
        
        // Test interest fee calculation
        let interest_fee = math::get_interest_fee(1_000_000_000, 30); // 30 days
        assert!(interest_fee > 0, 2);
        
        // Test midnight timestamp calculation
        let timestamp = math::get_midnight_timestamp(1_700_000_000);
        assert!(timestamp > 0, 3);
    }
    
    #[test]
    fun test_trading_functions() {
        let scenario = Scenario::new();
        let admin = scenario.address(0);
        let user = scenario.address(1);
        
        scenario.next_tx(admin, vector[]);
        
        // Initialize components
        let vault = trading::create_vault(&mut scenario.ctx());
        let (admin_cap, config) = admin::create_admin(&mut scenario.ctx());
        
        scenario.next_tx(user, vector[]);
        
        // Test get buy amount
        // Note: This is a simplified test, in practice we'd need more setup
    }
}
