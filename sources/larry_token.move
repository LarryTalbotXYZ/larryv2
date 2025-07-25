// Copyright (c) 2025 Larry Talbot. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

module larry_talbot::larry_token {
    use std::option;
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::balance::Balance;
    use sui::event;
    
    /// LARRY Token Type - One-time witness for coin creation
    struct LARRY has drop {}
    
    /// Event for token minting
    struct MintEvent has copy, drop {
        amount: u64,
        to: address
    }
    
    /// Event for token burning
    struct BurnEvent has copy, drop {
        amount: u64,
        from: address
    }
    
    /// Initialize the LARRY token
    fun init(witness: LARRY, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness, 
            9, // 9 decimals like SUI
            b"LARRY TALBOT",
            b"LARRY",
            b"LARRY TALBOT Token",
            option::none(),
            ctx
        );
        
        // Transfer to sender
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_transfer(metadata, tx_context::sender(ctx));
    }
    
    /// Mint new LARRY tokens
    public entry fun mint(treasury_cap: &mut coin::TreasuryCap<LARRY>, amount: u64, ctx: &mut TxContext) {
        let new_coin = coin::mint(treasury_cap, amount, ctx);
        event::emit(MintEvent { amount, to: tx_context::sender(ctx) });
        transfer::public_transfer(new_coin, tx_context::sender(ctx));
    }
    
    /// Burn LARRY tokens
    public entry fun burn(treasury_cap: &mut coin::TreasuryCap<LARRY>, coin_to_burn: coin::Coin<LARRY>, ctx: &mut TxContext) {
        let amount = coin::value(&coin_to_burn);
        coin::burn(treasury_cap, coin_to_burn);
        event::emit(BurnEvent { amount, from: tx_context::sender(ctx) });
    }
}
