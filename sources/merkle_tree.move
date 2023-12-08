module aptos_call::merkle_tree{
    use std::vector;
    use aptos_std::aptos_hash;
    use std::bcs;

    const BYTESLENGHTMISMATCH:u64 = 0;

    // const CONTRACT_ADDRESS: address = @sender_s;
    // const ADMIN: address = @admin;

    public fun verify(proof:vector<vector<u8>>,root:vector<u8>,leaf:vector<u8>):bool{
        let computedHash = leaf;
        assert!(vector::length(&root)==32,BYTESLENGHTMISMATCH);
        assert!(vector::length(&leaf)==32,BYTESLENGHTMISMATCH);
        let i = 0;
        while (i < vector::length(&proof)) {
            let proofElement=*vector::borrow_mut(&mut proof, i);
            if (compare_vector(& computedHash,& proofElement)==1) {
                vector::append(&mut computedHash,proofElement);
                computedHash = aptos_hash::keccak256(computedHash)
            }
            else{
                vector::append(&mut proofElement,computedHash);
                computedHash = aptos_hash::keccak256(proofElement)
            };
            i = i+1
        };
        computedHash == root
    }
    fun compare_vector(a:&vector<u8>,b:&vector<u8>):u8{
        let index = 0;
        while(index < vector::length(a)){
            if(*vector::borrow(a,index) > *vector::borrow(b,index)){
                return 0
            };
            if(*vector::borrow(a,index) < *vector::borrow(b,index)){
                return 1
            };
            index = index +1;
        };
        1
    }

    // transform address to vector<u8>
    #[view]
    public fun trans_address_vecu8(account:address):vector<u8>{
        let account_vec_bytes = bcs::to_bytes(&account);
        let account_vecu8 = aptos_hash::keccak256(account_vec_bytes);
        account_vecu8
    }

   #[test]
    fun test_merkle(){
        let leaf1=  x"d4dee0beab2d53f2cc83e567171bd2820e49898130a22622b10ead383e90bd77";
        let leaf2 = x"5f16f4c7f149ac4f9510d9cf8cf384038ad348b3bcdc01915f95de12df9d1b02";
        let leaf3 = x"c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470";
        let leaf4 = x"0da6e343c6ae1c7615934b7a8150d3512a624666036c06a92a56bbdaa4099751";
        // finding out the root
        let root1 = find_root(leaf1,leaf2);
        let root2 = find_root(leaf3,leaf4);
        let final_root = find_root(root1,root2);
        //the proofs
        let proof1 = vector[leaf2,root2];
        let proof2 = vector[leaf1,root2];
        let proof3 = vector[leaf4,root1];
        let proof4 = vector[leaf3,root1];
        //here
        assert!(verify(proof1,final_root,leaf1),99);
        assert!(verify(proof2,final_root,leaf2),100);
        assert!(verify(proof3,final_root,leaf3),101);
        assert!(verify(proof4,final_root,leaf4),102);
    }



    #[test]
    #[expected_failure(abort_code = 196609, location = Self)]
    fun test_failure(){
        let leaf1=  x"d4dee0beab2d53f2cc83e567171bd2820e49898130a22622b10ead383e90bd77";
        let leaf2 = x"5f16f4c7f149ac4f9510d9cf8cf384038ad348b3bcdc01915f95de12df9d1b02";
        let leaf3 = x"c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470";
        let leaf4 = x"0da6e343c6ae1c7615934b7a8150d3512a624666036c06a92a56bbdaa4099751";
        // finding out the root
        let root1 = find_root(leaf1,leaf2);
        let root2 = find_root(leaf3,leaf4);
        let final_root = find_root(root1,root2);
        //the proofs
        let proof1 = vector[leaf2,root2];
        let proof2 = vector[leaf1,root2];
        let proof3 = vector[leaf4,root1];
        let proof4 = vector[leaf3,root1];
        std::debug::print(&final_root);
        //here
        assert!(verify(proof1,final_root, x"0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"),196609);
        assert!(verify(proof2,final_root, x"0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"),196609);
        assert!(verify(proof3,final_root, x"0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"),196609);
        assert!(verify(proof4,final_root, x"0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"),196609);
    }
    public fun find_root(leaf1:vector<u8>,leaf2:vector<u8>):vector<u8>{
        let root= vector<u8>[];
        if (compare_vector(& leaf1,& leaf2)==1) {
                vector::append(&mut root,leaf1);
                vector::append(&mut root,leaf2);
                root = aptos_hash::keccak256(root);
            }
            else{
                vector::append(&mut root,leaf2);
                vector::append(&mut root,leaf1);
                root = aptos_hash::keccak256(root);
            };
        root
    }

    #[test]
    public fun keccak_256_address():vector<u8>{
        let account: vector<u8> = x"84801d3586d1afeb7be41fd95140e94bb1409b5b4fb490c156dd77625f10b73d";
        std::debug::print(&account);
        let account_vecu8 = aptos_hash::keccak256(account);
        std::debug::print(&account_vecu8);
        account_vecu8
    }

    #[test]
    public fun keccak_256_address_vec():vector<u8>{
        let account: vector<vector<u8>> = vector[
            x"5B38Da6a701c568545dCfcB03FcB875f56beddC4",
            x"Ab8483F64d9C6d1EcF9b849Ae677dD3315835cb2",
            x"4B20993Bc481177ec7E8f571ceCaE8A9e22C02db",
            x"78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB"
        ];
        
        std::debug::print(&account);
        let i = 0;
        let sum = 0;
        let len = vector::length(&account);
        while (i < len) {
            let account = *vector::borrow_mut(&mut account, i);
            let account_vecu8_temp = aptos_hash::keccak256(account);
            std::debug::print(&account_vecu8_temp);
            i = i + 1;
        };
         let account2: vector<u8> = x"84801d3586d1afeb7be41fd95140e94bb1409b5b4fb490c156dd77625f10b73d";
         account2
    }

    #[test]
    fun test_verfiy(){
        // hash function: keccak256 Options: hash leaves and sort pairs
        let leaf1 = x"999bf57501565dbd2fdcea36efa2b9aef8340a8901e3459f4a4c926275d36cdb";
        // proof
        let proof1 = vector[
            x"5931b4ed56ace4c46b68524cb5bcbf4195f1bbaacbe5228fbd090546c88dd229",
            x"4726e4102af77216b09ccd94f40daa10531c87c4d60bba7f3b3faf5ff9f19b3c"
        ];
        // root
        let root1 = x"eeefd63003e0e702cb41cd0043015a6e26ddb38073cc6ffeb0ba3e808ba8c097";
        let res = verify(proof1,root1,leaf1);
        std::debug::print(&res);
    }
    #[test]
    fun sum_of(): u64 {
        let values: vector<u64> = vector[1, 2, 3, 4, 5];
        let i = 0;
        let sum = 0;
        let len = vector::length(&values);
        while (i < len) {
            i = i + 1;
            sum = i;
        };
        std::debug::print(&sum);
        return sum
    }

}