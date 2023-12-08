module aptos_call::apt_inscription {
    use std::string::{Self,String};
    use std::signer;
    use std::block;
    use std::vector;
    use std::bcs;
    use std::signer::address_of;
    use aptos_std::aptos_hash;
    use aptos_std::table;
    use aptos_std::account;
    use aptos_token::token::{Self};
    use aptos_token::token_transfers;
    use aptos_framework::resource_account;
    use aptos_framework::event::{Self};
    use aptos_framework::guid;

    struct InscriptionData has store, key {
        id: guid::GUID,
        total_inscription: u64
    }
    struct Fee has store, key {
        id: guid::GUID,
        inscribe_apt20_fee: u64,
        inscribe_fee: u64,
        balance: u64,
        admin: address
    }
    struct InscriptionApt20 has store {
        p: String, // protocol , help other system identify and process brc20 events
        op: String, // operation ,type of event , mint , burn , transfer, deploy 
        tick: String, // ticket name 4 letters
        max: u64, // max number of the brc20 token
        amt: u64, // each brc20 token amount
        lim: u64, // optional ,
        dec : u64, // brc20 token decimal default 18
    }

    struct Apt20DeployEvent has copy, drop {
        module_id: address,
        share_id: guid::ID,
        tick: String,
        max: u64,
        amt: u64,
        lim: u64,
        deployer: address
    }
    struct Apt20MintEvent has copy, drop {
        tick: String,
        current_mint: u64
    }

    // deploy apt-20 incription


    // inscribe apt-20 incription


    // claim call token 


    // burn inscribe apt-20 incription and claim apt token
    
      


}