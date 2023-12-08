module aptos_call::nft_lottery {
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
    use aptos_call::merkle_tree;

    // errors
    const BYTESLENGHTMISMATCH:u64 = 0;
    const USER_HAS_CLAIMED: u64 = 11;
    const MERKLE_ROOT_IS_ALREADY_SET: u64 = 22;
    const ACTIVITY_ALREADY_EXISTS: u64 = 55;
    const IS_NOT_YOUR_ACTIVITY : u64 = 66;
    const ACITIVITY_ID_IS_ILLEGAL : u64 = 77;
    const ACTIVITY_IS_NOT_END : u64 = 88;
    const TOKEN_NAMES_LENGTH_NOT_EQUAL_AMOUNTS_LENGTH : u64 = 99;
    const MERKLE_PROOF_IS_ILLEGAL : u64 = 100;
    // contract owner
    const CONTRACT_ADDRESS: address = @aptos_call;
    const ADMIN: address = @admin;

    // activity
    struct ActivityKey has key,copy,drop {
        // everyone can orgnaize a activity
        organizer:address,
        // acitivity id
        activityId:u64
    }  

    struct UserActivityKey has key,copy,drop {
        user:address,
        // everyone can orgnaize a activity
        organizer:address,
        // acitivity id
        activityId:u64
    }   

    // activity info and a resource accoutn created by orgnizer that sotre nft assets
    struct ActivityInfo has key,store,copy {
        organizer: address,
        activityId: u64,
        tokenIds: vector<token::TokenId>,
        endBlockNumber: u64,
        merkleRoot: vector<u8>,
    }

    // activityInfos obtain by this CONTRAC_ADDRESS
    // user can search activityinfo with activity key , if user win prizes, he can find resource account to get his prize
    struct ActivityInfoS has key,store {
        activityInfos: table::Table<ActivityKey, ActivityInfo>
    }

    // user has claimed activity
    struct ClaimedActivity has key,store,drop {
        organizer: address,
        activityId: u64,
        claimer: address,
        tokenIds: vector<token::TokenId>,
    }

    // user claimed activitys obtain by this CONTRAC_ADDRESS
    struct ClaimedActivityS has key,store {
        claimedActivitys: table::Table<UserActivityKey, ClaimedActivity>
    }

    struct ModuleData has key {
        resource_signer_cap: account::SignerCapability,
    }

    // event
    struct CreateActivityEvent has drop,store{
        organizer: address,
        creators_address: address,
        collection:String,
        property_version:u64,
        activityId: u64,
        token_names: vector<String>,
        amounts: vector<u64>,
        endBlockNumber: u64,
    }

    struct MerkleRootEvent has drop,store{
        organizer: address,
        activityId: u64,
        merkleRoot: vector<u8>,
    }

    struct ClaimedEvent has drop,store{
        claimer: address,
        organizer: address,
        activityId: u64,
        creators_address: address,
        collection:String,
        property_version:u64,
        name:String,
        amount:u64
    }

    struct WithdrawPrizeEvent has drop,store{
        organizer: address,
        activityId: u64,
        remainPrizes: vector<token::TokenId>,
    }

    struct NftLotteryEvents has key {
        create_acitivity_events: event::EventHandle<CreateActivityEvent>,
        merkle_root_events: event::EventHandle<MerkleRootEvent>,
        claimed_events: event::EventHandle<ClaimedEvent>,
        withdraw_prize_events: event::EventHandle<WithdrawPrizeEvent>,
    }

    //
    // @notice initialize the module and store the resource account signer capability
    //
    //         Note: this function can only be called once,and must use resource account to call this function when publish contract
    // 
    // @param organizer the activity owner
    // @param creators_address the nft contract creator address
    // @param collection the nft contract collection name
    // @param property_version the nft token property version default 0
    // @param activityId the activity id
    // @param token_names the nft token name vector which will be transfered to resource account
    // @param amounts the nft token amount vector which will be transfered to resource account
    // @param endBlockNumber the activity end block number
    //
    fun init_module(account: &signer) {
        // store the capabilities within `ModuleData`
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(account, @source);
        move_to(account, ModuleData {
            resource_signer_cap
        });
        // if contract address have not ActivityInfos then create this database
        if (!exists<ActivityInfoS>(CONTRACT_ADDRESS)) {
            move_to(account, ActivityInfoS {
                activityInfos: table::new()
            });
        };
        // if contract address have not ClaimedActivitys then create this database
        if (!exists<ClaimedActivityS>(CONTRACT_ADDRESS)) {
            move_to(account, ClaimedActivityS {
                claimedActivitys: table::new()
            });
        };
        // if contract address have not NftLotteryEvents then create this database
        if (!exists<NftLotteryEvents>(CONTRACT_ADDRESS)) {
            move_to(account, NftLotteryEvents {
                create_acitivity_events: account::new_event_handle<CreateActivityEvent>(account),
                merkle_root_events: account::new_event_handle<MerkleRootEvent>(account),
                claimed_events: account::new_event_handle<ClaimedEvent>(account),
                withdraw_prize_events: account::new_event_handle<WithdrawPrizeEvent>(account),
            });
        };
    }

    /* ========== CREATE ACTIVITY ========== */
    /**
     * @notice Creates a new activity if it does not exist.
     *
     *         Note: This method will revert if the activity already exists.
     * 
     * @param organizer the activity owner
     * @param creators_address the nft contract creator address
     * @param collection the nft contract collection name
     * @param property_version the nft token property version default 0
     * @param activityId the activity id
     * @param token_names the nft token name vector which will be transfered to resource account
     * @param amounts the nft token amount vector which will be transfered to resource account
     * @param endBlockNumber the activity end block number
     */
    public entry fun createActivity(
        organizer: &signer,
        creators_address: address,
        collection:String,
        property_version:u64,
        activityId: u64,
        token_names: vector<String>,
        amounts: vector<u64>,
        endBlockNumber: u64,
    )  acquires ActivityInfoS,ModuleData,NftLotteryEvents{
        // token_names vector length must equal amounts vector length
        assert!(vector::length(&token_names) == vector::length(&amounts), TOKEN_NAMES_LENGTH_NOT_EQUAL_AMOUNTS_LENGTH);
        // gnenrate TokenId
        let index = 0 ;
        // length
        let length = vector::length(&token_names);
        // tokenId vector
        let token_ids: vector<token::TokenId> = vector::empty();
        while(index < length){
            let name = *vector::borrow(&token_names, index);
            let token_id = token::create_token_id_raw(creators_address, collection, name, property_version);
            vector::push_back(&mut token_ids, token_id);
            index = index + 1;
        };

        // create new activity instance
        let activityInfo: ActivityInfo = ActivityInfo {
            organizer: address_of(organizer),
            activityId: activityId,
            tokenIds: token_ids,
            endBlockNumber: endBlockNumber,
            merkleRoot: vector::empty(),
        };
        let activityKey: ActivityKey = ActivityKey {
            organizer: address_of(organizer),
            activityId,
        };

        // add activity info to contract account 
        let activityInfos = borrow_global_mut<ActivityInfoS>(CONTRACT_ADDRESS);
        // check activityId is exist
        assert!(!table::contains(&activityInfos.activityInfos, activityKey), ACTIVITY_ALREADY_EXISTS);
        table::add(&mut activityInfos.activityInfos, activityKey, activityInfo);  
        let _module_data = borrow_global_mut<ModuleData>(CONTRACT_ADDRESS);
        let i = 0;
        let len = vector::length(&token_ids);
        // resource_account
        let module_data = borrow_global_mut<ModuleData>(CONTRACT_ADDRESS);
        let resource_signer = account::create_signer_with_capability(&module_data.resource_signer_cap);
        while (i < len) {
            let token_id = *vector::borrow(&token_ids, i);
            let amount = *vector::borrow(&amounts, i);
            let token = token::withdraw_token(organizer, token_id, amount);
            token::deposit_token(&resource_signer, token);
            i = i + 1;
        };
        // emit event
        let nft_lottery_events = borrow_global_mut<NftLotteryEvents>(CONTRACT_ADDRESS);
        event::emit_event<CreateActivityEvent>(
            &mut nft_lottery_events.create_acitivity_events,
            CreateActivityEvent {
                organizer: address_of(organizer),
                creators_address,
                collection,
                property_version,
                activityId,
                token_names,
                amounts,
                endBlockNumber,
            },
        );

    }

    // ========== CLAIM PRIZE ========== */
    //
    // @notice Users can claim their tokens if they have not already claimed.
    //         Note: This method will revert if the activity does not exist.
    //         only pass merkle proof can claim token.
    //  
    // @param receiver one of winners who can claim token
    // @param organizer the activity owner
    // @param creators_address the nft contract creator address
    // @param collection the nft contract collection name
    // @param property_version the nft token property version default 0
    // @param name the nft token name
    // @param activityId the activity id
    // @param merkleProof the merkle proof
    //
    public entry fun claim(
        receiver : &signer,
        organizer: address,
        creators_address: address,
        collection:String,
        property_version:u64,
        name: String,
        activityId: u64,
        merkleProof: vector<vector<u8>>
    ) acquires ActivityInfoS,ModuleData,ClaimedActivityS,NftLotteryEvents{
        let token_id = token::create_token_id_raw(creators_address, collection, name, property_version);
        let receiver_address: address = address_of(receiver);
        let activityKey: ActivityKey = ActivityKey {
            organizer,
            activityId,
        };
        let userActivityKey: UserActivityKey = UserActivityKey {
            user:receiver_address,
            organizer,
            activityId,
        };
        // check activity key 
        let all_activity_infos = borrow_global_mut<ActivityInfoS>(CONTRACT_ADDRESS);
        assert!(table::contains(&all_activity_infos.activityInfos, activityKey), ACITIVITY_ID_IS_ILLEGAL);
        // get merkle root from activity info
        let activityInfo = table::borrow(&all_activity_infos.activityInfos, activityKey);
        let merkleRoot = activityInfo.merkleRoot;
        // check merkle proof
        let leaf = aptos_hash::keccak256(bcs::to_bytes(&receiver_address));
        assert!(merkle_tree::verify(merkleProof, merkleRoot, leaf), MERKLE_PROOF_IS_ILLEGAL);
        // check user is not claimed
        let all_claimed_activitys = borrow_global_mut<ClaimedActivityS>(CONTRACT_ADDRESS);
        assert!(!table::contains(&all_claimed_activitys.claimedActivitys, userActivityKey), USER_HAS_CLAIMED);
        // find resource account
        let module_data = borrow_global_mut<ModuleData>(CONTRACT_ADDRESS);
        let resource_signer = account::create_signer_with_capability(&module_data.resource_signer_cap);
        // transfer nft prize from resource accoutn to winner
        let token = token::withdraw_token(&resource_signer, token_id, 1);
        token::deposit_token(receiver, token);
        // remove token_id from activityInfo
        let activityInfo = table::borrow_mut(&mut all_activity_infos.activityInfos, activityKey);
        vector::remove_value(&mut activityInfo.tokenIds, &token_id);
        // record claimed activity
        let token_ids = vector::empty();
        vector::push_back(&mut token_ids, token_id);
        let claimedActivity: ClaimedActivity = ClaimedActivity {
            organizer,
            activityId,
            claimer: receiver_address,
            tokenIds: token_ids,
        };
        let claimedActivityKey: UserActivityKey = UserActivityKey {
            user:receiver_address,
            organizer,
            activityId,
        };
        table::add(&mut all_claimed_activitys.claimedActivitys, claimedActivityKey, claimedActivity);
        // emit event
        let nft_lottery_events = borrow_global_mut<NftLotteryEvents>(CONTRACT_ADDRESS);
        event::emit_event<ClaimedEvent>(
            &mut nft_lottery_events.claimed_events,
            ClaimedEvent {
                claimer: receiver_address,
                organizer,
                activityId,
                creators_address,
                collection,
                property_version,
                name,
                amount: 1,
            },
        );
    }

    // ========== SET MERKLETREE ROOT ========== */
    //
    // @notice Sets the merkle root of an activity.
    //         Note: This method will revert if the activity does not exist.
    //         and only organizer can set merkle root. and organizer can only set merkle root before endBlockNumber.
    //  
    // @param caller the activity owner
    // @param activityId the activity id
    // @param merkleRoot the merkle root
    //
    public entry fun setMerkleRoot(caller :&signer,activityId: u64, merkleRoot: vector<u8>) acquires ActivityInfoS,NftLotteryEvents{
        let caller_address: address = address_of(caller);
        let activityKey: ActivityKey = ActivityKey {
            organizer: caller_address,
            activityId: activityId,
        };
        let activityInfo = table::borrow_mut(&mut borrow_global_mut<ActivityInfoS>(CONTRACT_ADDRESS).activityInfos, activityKey);
        assert!(activityInfo.organizer == caller_address, IS_NOT_YOUR_ACTIVITY);
        // append merkle root to activity info
        assert!(vector::length(&merkleRoot) >0, MERKLE_ROOT_IS_ALREADY_SET);
        vector::append(&mut activityInfo.merkleRoot, merkleRoot);
        // emit event
        let nft_lottery_events = borrow_global_mut<NftLotteryEvents>(CONTRACT_ADDRESS);
        event::emit_event<MerkleRootEvent>(
            &mut nft_lottery_events.merkle_root_events,
            MerkleRootEvent {
                organizer: caller_address,
                activityId,
                merkleRoot,
            },
        );
    }


    // ========== RESTRICTED FUNCTIONS ========== */
    //
    // @notice Only organizer  can withdraw tokenIds to organizer.
    //         Note: This method will help organizer withdraw tokenIds to organizer.
    //  
    // @param organizer the activity owner
    // @param activityId the activity id
    //
    public entry fun withDrawRemainPrizesByActivityId(
        organizer: &signer,
        activityId: u64,
    ) acquires ActivityInfoS,ModuleData,NftLotteryEvents{
        let activityKey: ActivityKey = ActivityKey {
            organizer: address_of(organizer),
            activityId,
        };
        // get activity info by activity key
        let all_activity_infos = borrow_global_mut<ActivityInfoS>(CONTRACT_ADDRESS);
        // assert contains this activity key
        assert!(table::contains(&all_activity_infos.activityInfos, activityKey), ACITIVITY_ID_IS_ILLEGAL);
        // get activity info
        let activityInfo = table::borrow_mut(&mut all_activity_infos.activityInfos, activityKey);
        // check organizer is activity organizer
        assert!(address_of(organizer) == activityInfo.organizer, IS_NOT_YOUR_ACTIVITY);
        // check activity is end
        assert!(block::get_current_block_height() > activityInfo.endBlockNumber, ACTIVITY_IS_NOT_END);
        // get resource account cap
        let module_data = borrow_global<ModuleData>(CONTRACT_ADDRESS);
        let resource_signer_cap = &module_data.resource_signer_cap;
        let resource_signer = account::create_signer_with_capability(resource_signer_cap);
        // withdraw prize
        let i = 0;
        let len = vector::length(&activityInfo.tokenIds);
        while (i < len) {
            let token_id = *vector::borrow(&activityInfo.tokenIds, i);
            token_transfers::offer(&resource_signer, address_of(organizer), token_id, 1);
            i = i + 1;
        };
        // emit event
        let nft_lottery_events = borrow_global_mut<NftLotteryEvents>(CONTRACT_ADDRESS);
        event::emit_event<WithdrawPrizeEvent>(
            &mut nft_lottery_events.withdraw_prize_events,
            WithdrawPrizeEvent {
                organizer: address_of(organizer),
                activityId,
                remainPrizes: activityInfo.tokenIds,
            },
        );

    }

    // ==========VIEW FUNCTIONS ========== */
    //
    // @notice Check user has claimed activity.
    //         Note: If user has claimed activity, return true, else return false.
    // @param user the user address
    // @param organizer the activity owner
    // @param activityId the activity id
    //
    #[view]
    public fun checkHasClaimInfo(
        user: address,
        organizer: address,
        activityId: u64,
    ):bool acquires ClaimedActivityS{
        let userActivityKey: UserActivityKey = UserActivityKey {
            user,
            organizer,
            activityId,
        };
        let all_claimed_activitys = borrow_global_mut<ClaimedActivityS>(CONTRACT_ADDRESS);
        let has_claimed = table::contains(&all_claimed_activitys.claimedActivitys, userActivityKey);
        has_claimed
    }

    // ==========VIEW FUNCTIONS ========== */
    //
    // @notice Get activity Merkle Root
    //         Note: If Organizer has set merkle root, return merkle root, else return empty vector.
    // @param organizer the activity owner
    // @param activityId the activity id
    //
    #[view]
    public fun getMerkleRoot(
        organizer: address,
        activityId: u64,
    ):vector<u8> acquires ActivityInfoS {
        let activityKey: ActivityKey = ActivityKey {
            organizer,
            activityId,
        };
        // check activity key 
        let all_activity_infos = borrow_global_mut<ActivityInfoS>(CONTRACT_ADDRESS);
        assert!(table::contains(&all_activity_infos.activityInfos, activityKey), ACITIVITY_ID_IS_ILLEGAL);
        // get merkle root from activity info
        let activityInfo = table::borrow(&all_activity_infos.activityInfos, activityKey);
        let merkleRoot = activityInfo.merkleRoot;
        // bcs root to vector<u8>
        let merkleRootVec = bcs::to_bytes(&merkleRoot);
        merkleRootVec
    }

    // ==========VIEW FUNCTIONS ========== */
    //
    // @notice Check user is in activity winner list.
    //         Note: If user is in activity winner list, return true, else return false.
    // @param organizer the activity owner
    // @param activityId the activity id
    // @param merkleProof the merkle proof of user
    //
    #[view]
    public fun checkUserInWhiteList(
        user: &signer,
        organizer: address,
        activityId: u64,
        merkleProof: vector<vector<u8>>
    ):bool acquires ActivityInfoS {
        let activityKey: ActivityKey = ActivityKey {
            organizer,
            activityId,
        };
        // check activity key 
        let all_activity_infos = borrow_global_mut<ActivityInfoS>(CONTRACT_ADDRESS);
        assert!(table::contains(&all_activity_infos.activityInfos, activityKey), ACITIVITY_ID_IS_ILLEGAL);
        // get merkle root from activity info
        let activityInfo = table::borrow(&all_activity_infos.activityInfos, activityKey);
        let merkleRoot = activityInfo.merkleRoot;
        // check merkle proof
        let user_address = signer::address_of(user);
        let leaf = aptos_hash::keccak256(bcs::to_bytes(&user_address));
        let checkResult = merkle_tree::verify(merkleProof, merkleRoot, leaf);
        checkResult
    }

    // ==========VIEW FUNCTIONS ========== */
    //
    // @notice get activity info by activity key
    //
    // @param organizer the activity owner
    // @param activityId the activity id
    //
    #[view]
    public fun getActivityInfo(
        organizer: address,
        activityId: u64,
    ):ActivityInfo acquires ActivityInfoS {
        let activityKey: ActivityKey = ActivityKey {
            organizer,
            activityId,
        };
        let all_activity_infos_table = &borrow_global<ActivityInfoS>(CONTRACT_ADDRESS).activityInfos;
        // assert contains this activity key
        assert!(table::contains(all_activity_infos_table, activityKey), ACITIVITY_ID_IS_ILLEGAL);
        let activityInfo = table::borrow(all_activity_infos_table, activityKey);
        *activityInfo
    }

    // ==========VIEW FUNCTIONS ========== */
    //
    // @notice get resource account address
    //
    #[view]
    public fun getResourceAccount():address acquires ModuleData {
        let module_data = borrow_global<ModuleData>(CONTRACT_ADDRESS);
        let resource_signer = account::create_signer_with_capability(&module_data.resource_signer_cap);
        address_of(&resource_signer)
    }

    // ==========VIEW FUNCTIONS ========== */
    //
    // @notice get admin address
    //
    #[view]
    public fun getAdmin():address {
        ADMIN
    }




    // ==========UTILS FUNCTIONS ========== */
    //
    // @notice batch offer token
    //         Note: This method will help user batch offer token to user. and user must click accept button to accept token.
    //  
    // @param from the nft owner
    // @param to the nft receiver
    // @param creators_address the nft creators address
    // @param collection the nft collection name
    // @param token_names the nft token names
    // @param property_version the nft property version default is 0
    // @param amounts the nft amounts
    //
    public entry fun batchOfferToken(
        from: &signer,
        to: address,
        creators_address: address,
        collection:String,
        token_names: vector<String>,
        property_version:u64,
        amounts: vector<u64>,
    )  {
        // gnenrate TokenId
        let index = 0 ;
        // length
        let length = vector::length(&token_names);
        // tokenId vector
        let token_ids: vector<token::TokenId> = vector::empty();
        while(index < length){
            let name = *vector::borrow(&token_names, index);
            let token_id = token::create_token_id_raw(creators_address, collection, name, property_version);
            vector::push_back(&mut token_ids, token_id);
            index = index + 1;
        };
        // transfer token
        let i = 0;
        let len = vector::length(&token_ids);
        while (i < len) {
            let token_id = *vector::borrow(&token_ids, i);
            let amount = *vector::borrow(&amounts, i);
            token_transfers::offer(from, to, token_id, amount);
            i = i + 1;
        };
    }
    
    // ==========UTILS FUNCTIONS ========== */
    //
    // @notice batch transfer token 
    //         Note: This method will help user batch transfer token to user, and user will receive token immediately.
    //  
    // @param organizer the activity owner
    // @param activityId the activity id
    //
    public entry fun batchTransferToken(
        from: &signer,
        to: &signer,
        creators_address: address,
        collection:String,
        token_names: vector<String>,
        property_version:u64,
        amounts: vector<u64>,
    )  {
        // gnenrate TokenId
        let index = 0 ;
        // length
        let length = vector::length(&token_names);
        // tokenId vector
        let token_ids: vector<token::TokenId> = vector::empty();
        while(index < length){
            let name = *vector::borrow(&token_names, index);
            let token_id = token::create_token_id_raw(creators_address, collection, name, property_version);
            vector::push_back(&mut token_ids, token_id);
            index = index + 1;
        };
        // transfer token
        let i = 0;
        let len = vector::length(&token_ids);
        while (i < len) {
            let token_id = *vector::borrow(&token_ids, i);
            let amount = *vector::borrow(&amounts, i);
            let token = token::withdraw_token(from, token_id, amount);
            token::deposit_token(to, token);
            i = i + 1;
        };
    }

    // ==========UTILS FUNCTIONS ========== */
    //
    // @notice verify merkle proof
    //         Note: This method will verify merkle proof.
    // example:
    // let proof = [29c4d529256c89d1ceeb62903dd6027ba1c47dfdaf9aaf3e057d181871c44ce4,2b89f3ceea8b6df3c5abb0e578dddd3f82e26e7d8ac1d7d3a6480e27b7ce8c89];
    // let root = 0x1d942d5f18801e1e2df2bc869d7cd5a70a161ed7f4f91608ee1dbdcb08e91e8a
    // let leaf = 0xb844245bf026ac2fa77cd814ab778afb4876728386180beba40c88ccebd17fa3
    //
    // @param proof the merkle proof of user
    // @param root the merkle root
    // @param leaf the merkle leaf is  sha3(userAddress)
    //
    #[view]
    public fun verifyMerkleTree(proof:vector<vector<u8>>,root:vector<u8>,leaf:vector<u8>):bool{
        let result = merkle_tree::verify(proof,root,leaf);
        result
    }

    // create nft collection and mint nft
    #[test(creator = @aptos_call)]
    public entry fun create_nft_collection_and_mint_10times_nft(creator : signer) {
        std::debug::print(&1234);
        account::create_account_for_test(address_of(&creator));
        // collection  basic info 
        let collection_name = string::utf8(b"Doodles");
        let property_version = 1;
        let collection_desc = string::utf8(b"This is a Doodles Collection Desc!");
        let collection_url = string::utf8(b"https://www.doodles.com");
        let collection_max = 1;
        let collection_mutate_setting = vector<bool>[false, false, false];

        token::create_collection(
            &creator,
            collection_name,
            collection_desc,
            collection_url,
            collection_max,
            collection_mutate_setting
        );

        // create nft token data
        let collection = string::utf8(b"Doodles");
        let token_name = string::utf8(b"Doodles#");
        let token_description = string::utf8(b"This is a Doodles#1 Token Desc!");

        let token_maximum = 10000;
        let token_uri = string::utf8(b"https://i.seadn.io/gcs/files/3ec77d5814ebd29dfd49e6e78c30ce93.png?auto=format&dpr=1&w=1000");
        let royalty_payee_address = address_of(&creator);
        let royalty_points_denominator = 10000;
        let royalty_points_numerator = 1000;
        let mutate_setting = vector<bool>[false, false, false, false, false];
        let property_keys = vector<String>[];
        let property_values = vector<vector<u8>>[];
        let property_types = vector<String>[];
        let token_mut_config = token::create_token_mutability_config(&mutate_setting);

        let tokendata_id = token::create_tokendata(
            &creator,
            collection,
            token_name,
            token_description,
            token_maximum,
            token_uri,
            royalty_payee_address,
            royalty_points_denominator,
            royalty_points_numerator,
            token_mut_config,
            property_keys,
            property_values,
            property_types
        );
        // mint nft
        let token_balance = 10;
        token::mint_token(
            &creator,
            tokendata_id,
            token_balance
        );
        let token_id = token::create_token_id_raw(address_of(&creator), collection, token_name, property_version);
        // check nft balance
        let balance = token::balance_of(address_of(&creator), token_id);
        std::debug::print(&balance);
    }    

    // test merkle proof
    #[test(creator = @aptos_call)]
    public entry fun test_merkle_tree(){
        let root = x"a98f3c03bb8cd3ed1916e74ba1c29aaa78ef88e15d839077bcca9eae9aa5fad8";
        let leaf = x"39af6499dd5ddeddab82267004e7ff2743b48e53e7542d4821e87282dca08604";
        let proof = vector[
            x"2b89f3ceea8b6df3c5abb0e578dddd3f82e26e7d8ac1d7d3a6480e27b7ce8c89",
            x"5d3c17cb016604818ec4facd302d35a33c1ec8bf254c7c1e141bd26b69ede292"
        ];
        let result = merkle_tree::verify(proof,root,leaf);
        assert!(result, 1);
    }
    

    #[test(creator = @aptos_call,user1 = @0x010c5bb45478d6291bcfb220988b570acf7ca7b17f82ceb7944846fb7684de74)]
    public entry fun test_merkle_tree_with_leaf_address_param(user1 :signer){
        let root = x"a98f3c03bb8cd3ed1916e74ba1c29aaa78ef88e15d839077bcca9eae9aa5fad8";
        let root_vu8 : vector<u8> = vector::empty();
        vector::append(&mut root_vu8, root);
        assert!(root_vu8==root, 1);
        std::debug::print(&root_vu8);
        let user1_address = signer::address_of(&user1);
        let leaf_from_address = aptos_hash::keccak256(bcs::to_bytes(&user1_address));
        assert!(leaf_from_address == x"39af6499dd5ddeddab82267004e7ff2743b48e53e7542d4821e87282dca08604", 1);
        let proof = vector[
            x"2b89f3ceea8b6df3c5abb0e578dddd3f82e26e7d8ac1d7d3a6480e27b7ce8c89",
            x"5d3c17cb016604818ec4facd302d35a33c1ec8bf254c7c1e141bd26b69ede292"
        ];
        let result = merkle_tree::verify(proof,root_vu8,leaf_from_address);
        assert!(result, 1);
    }
}