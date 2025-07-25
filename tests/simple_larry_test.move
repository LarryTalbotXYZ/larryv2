// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module larry_talbot::simple_larry_test {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::Coin;
    use sui::tx_context::TxContext;
    use larry_talbot::simple_larry::{Self, LARRY};
    
    #[test]
    fun test_larry_token() {
        let scenario = Scenario::new();
        let admin = scenario.address(0);
        
        scenario.next_tx(admin, vector[]);
        
        // Initialize the LARRY token
        let larry_witness = LARRY {};
        simple_larry::init(larry_witness, &mut scenario.ctx());
        
        // Take the treasury cap
        let mut treasury_cap = scenario.take::<coin::TreasuryCap<LARRY>>(admin);
        
        scenario.next_tx(admin, vector[]);
        
        // Mint some LARRY tokens
        simple_larry::mint(&mut treasury_cap, 1000000000, &mut scenario.ctx());
        
        // Verify we got the coins
        let coins = scenario.take::<Coin<LARRY>>(admin);
        assert!(coin::value(&coins) == 1000000000, 0);
        
        scenario.restore(treasury_cap);
        scenario.restore(coins);
    }
}
