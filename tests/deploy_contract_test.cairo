%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_contract_address

const RESOURCE_CONTRACT = 1;
const LORDS_CONTRACT = 2;
const S_REALM_CONTRACT = 3;
const REALM_CONTRACT = 4;
const COMBAT_MODULE = 5;
const BOUNTY_COUNT_LIMIT = 6;
const BOUNTY_DEADLINE_LIMIT = 7;
const DEV_FEES = 8;

@external
func test_deploy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    let (self_address) = get_contract_address();
    %{
        import numpy as np
        lords_limit_amount = [10, 0]
        resources_amount = [10, 0]
        resource_len = token_ids_len = 4
        token_ids = [0, 0, 1, 0, 2, 0, 3, 0]
        resources_amount_array = resource_len*resources_amount 
        mercenary_address = deploy_contract("./contracts/mercenary.cairo", 
                       [ids.self_address, 
                        ids.REALM_CONTRACT, 
                        ids.S_REALM_CONTRACT, 
                        ids.RESOURCE_CONTRACT,
                        ids.LORDS_CONTRACT, 
                        ids.COMBAT_MODULE, 
                        ids.DEV_FEES, 
                        ids.BOUNTY_COUNT_LIMIT,
                        *lords_limit_amount, 
                        ids.BOUNTY_DEADLINE_LIMIT,
                        resource_len, 
                        *resources_amount_array,
                        token_ids_len,
                        *token_ids]).contract_address
        owner = load(mercenary_address, "Ownable_owner", "felt")[0]
        realms_contract = load(mercenary_address, "realm_contract", "felt")[0]
        staked_realms_contract = load(mercenary_address, "staked_realm_contract", "felt")[0]
        resources_contract = load(mercenary_address, "erc1155_contract", "felt")[0]
        lords_contract = load(mercenary_address, "lords_contract", "felt")[0]
        combat_module = load(mercenary_address, "combat_module", "felt")[0]
        dev_fess = load(mercenary_address, "developer_fees_percentage", "felt")[0]
        dev_fees_perc = load(mercenary_address, "developer_fees_percentage", "felt")[0]
        bounty_count_limit = load(mercenary_address, "bounty_count_limit", "felt")[0]
        bounty_amount_limit_lords = load(mercenary_address, "bounty_amount_limit_lords", "Uint256")
        bounty_deadline_limit = load(mercenary_address, "bounty_deadline_limit", "felt")[0]

        ## check that the bounty_amount_limit_resources storage was correctly filled
        for i in range(0, 4):
            if (i%2 == 0):
                resource_amount = load(mercenary_address, "bounty_amount_limit_resources", "Uint256", [token_ids[i], token_ids[i+1]])
                resource_amount_true = [resources_amount_array[i], resources_amount_array[i+1]] 
                assert resource_amount == resource_amount_true, f'resource amount in contract is {resource_amount} while should be {resource_amount_true}'

        assert owner == ids.self_address, f'owner error, expected {ids.self_address}, got {owner}'
        assert realms_contract == ids.REALM_CONTRACT, f'realms_contract error, expected {ids.REALM_CONTRACT}, got {realms_contract}'
        assert staked_realms_contract == ids.S_REALM_CONTRACT, f's_realms_contract error, expected {ids.S_REALM_CONTRACT}, got {staked_realms_contract}'
        assert resources_contract == ids.RESOURCE_CONTRACT, f'resource_contract error, expected {ids.RESOURCE_CONTRACT}, got {resources_contract}'
        assert lords_contract == ids.LORDS_CONTRACT, f'lords_contract error, expected {ids.LRODS_CONTRACT}, got {lords_contract}'
        assert combat_module == ids.COMBAT_MODULE, f'combat_module error, expected {ids.COMBAT_MODULE}, got {combat_module}'
        assert dev_fees_perc == ids.DEV_FEES, f'dev fees error, exepcted {ids.DEV_FEES}, got {dev_fees_perc}'
        assert bounty_count_limit == ids.BOUNTY_COUNT_LIMIT, f'bounty count limit error, expected {ids.BOUNTY_COUNT_LIMIT}, got {bounty_count_limit}' 
        assert bounty_amount_limit_lords == lords_limit_amount, f'lords limit amount error, expected {lords_limit_amount}, got {bounty_amount_limit_lords}'
        assert bounty_deadline_limit == ids.BOUNTY_DEADLINE_LIMIT, f'bounty deadline limit error, expected {bounty_deadline_limit}, got {ids.BOUNTY_DEADLINE_LIMIT}'
    %}
    return ();
}
