%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_contract_address
from starkware.cairo.common.uint256 import Uint256

from contracts.interface import IMercenary

const RESOURCE_CONTRACT = 1;
const LORDS_CONTRACT = 2;
const S_REALM_CONTRACT = 3;
const REALM_CONTRACT = 4;
const COMBAT_MODULE = 5;
const BOUNTY_COUNT_LIMIT = 6;
const BOUNTY_DEADLINE_LIMIT = 7;
const DEV_FEES = 8;

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    local mercenary_address;
    let (self_address) = get_contract_address();
    // deploy the mercenary contract
    %{
        import numpy as np
        lords_limit_amount = [10, 0]
        resources_amount = [10, 0]
        resource_len = token_ids_len = 4
        # token ids 1, 2, 3, 4
        token_ids = [1, 0, 2, 0, 3, 0, 4, 0]
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
        ids.mercenary_address = mercenary_address
        context.mercenary_address = mercenary_address
    %}
    // get values through getters
    let (dev_fees_perc) = IMercenary.view_developer_fees_percentage(
        contract_address=mercenary_address
    );
    let (bounty_count_limit) = IMercenary.view_bounty_count_limit(
        contract_address=mercenary_address
    );
    let (bounty_amount_limit_lords) = IMercenary.view_bounty_amount_limit_lords(
        contract_address=mercenary_address
    );
    let (bounty_amount_limit_resources) = IMercenary.view_bounty_amount_limit_resources(
        contract_address=mercenary_address, resources=Uint256(1, 0)
    );
    let (bounty_deadline_limit) = IMercenary.view_bounty_deadline_limit(
        contract_address=mercenary_address
    );

    // verify that the values are the correct ones
    %{
        ## check that the bounty_amount_limit_resources storage was correctly filled
        for i in range(0, 4):
            if (i%2 == 0):
                resource_amount = load(mercenary_address, "bounty_amount_limit_resources", "Uint256", [token_ids[i], token_ids[i+1]])
                resource_amount_true = [resources_amount_array[i], resources_amount_array[i+1]] 
                assert resource_amount == resource_amount_true, f'resource amount in contract is {resource_amount} while should be {resource_amount_true}'

        # values not accessible through getters
        ## retrieve
        owner = load(mercenary_address, "Ownable_owner", "felt")[0]
        realms_contract = load(mercenary_address, "realm_contract", "felt")[0]
        staked_realms_contract = load(mercenary_address, "staked_realm_contract", "felt")[0]
        resources_contract = load(mercenary_address, "erc1155_contract", "felt")[0]
        lords_contract = load(mercenary_address, "lords_contract", "felt")[0]
        combat_module = load(mercenary_address, "combat_module", "felt")[0]

        ## compare
        assert owner == ids.self_address, f'owner error, expected {ids.self_address}, got {owner}'
        assert realms_contract == ids.REALM_CONTRACT, f'realms_contract error, expected {ids.REALM_CONTRACT}, got {realms_contract}'
        assert staked_realms_contract == ids.S_REALM_CONTRACT, f's_realms_contract error, expected {ids.S_REALM_CONTRACT}, got {staked_realms_contract}'
        assert resources_contract == ids.RESOURCE_CONTRACT, f'resource_contract error, expected {ids.RESOURCE_CONTRACT}, got {resources_contract}'
        assert lords_contract == ids.LORDS_CONTRACT, f'lords_contract error, expected {ids.LRODS_CONTRACT}, got {lords_contract}'
        assert combat_module == ids.COMBAT_MODULE, f'combat_module error, expected {ids.COMBAT_MODULE}, got {combat_module}'

        # values retrieved through getters
        ## compare
        assert ids.dev_fees_perc == ids.DEV_FEES, f'dev fees error, exepcted {ids.DEV_FEES}, got {dev_fees_perc}'
        assert ids.bounty_count_limit == ids.BOUNTY_COUNT_LIMIT, f'bounty count limit error, expected {ids.BOUNTY_COUNT_LIMIT}, got {bounty_count_limit}' 

        bounty_amount_limit_lords = reflect(ids).bounty_amount_limit_lords.get()
        assert [bounty_amount_limit_lords.low, bounty_amount_limit_lords.high] == lords_limit_amount, \
        f'lords limit amount error, expected {lords_limit_amount}, got {bounty_amount_limit_lords}'

        bounty_amount_limit_resources = reflect(ids).bounty_amount_limit_resources.get()
        assert [bounty_amount_limit_resources.low, bounty_amount_limit_resources.high] == [resources_amount_array[2], resources_amount_array[3]], \
        f'lords limit amount error, expected {[resources_amount_array[2], resources_amount_array[3]]}, got {bounty_amount_limit_resources}'

        assert ids.bounty_deadline_limit == ids.BOUNTY_DEADLINE_LIMIT, \
        f'bounty deadline limit error, expected {bounty_deadline_limit}, got {ids.BOUNTY_DEADLINE_LIMIT}'
    %}
    return ();
}

@external
func test_setters{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    alloc_locals;

    local mercenary_address;

    const NEW_FEES = 1000;
    const NEW_BOUNTY_COUNT_LIMIT = 1100;
    const NEW_AMOUNT_LIMIT_LORDS = 1200;
    const NEW_AMOUNT_LIMIT_RESOURCES = 1300;
    const NEW_DEADLINE_LIMIT = 1400;

    %{ ids.mercenary_address = context.mercenary_address %}

    // test setters
    IMercenary.set_developer_fees_percentage(
        contract_address=mercenary_address, developer_fees_percentage_=NEW_FEES
    );
    IMercenary.set_bounty_count_limit(
        contract_address=mercenary_address, bounty_count_limit_=NEW_BOUNTY_COUNT_LIMIT
    );
    IMercenary.set_bounty_amount_limit_lords(
        contract_address=mercenary_address,
        bounty_amount_limit_lords_=Uint256(NEW_AMOUNT_LIMIT_LORDS, 0),
    );
    IMercenary.set_bounty_amount_limit_resources(
        contract_address=mercenary_address,
        resources=Uint256(1, 0),
        bounty_amount_limit_resources_=Uint256(NEW_AMOUNT_LIMIT_RESOURCES, 0),
    );
    IMercenary.set_bounty_deadline_limit(
        contract_address=mercenary_address, bounty_deadline_limit_=NEW_DEADLINE_LIMIT
    );

    %{
        dev_fees_perc = load(context.mercenary_address, "developer_fees_percentage", "felt")[0]
        assert dev_fees_perc == ids.NEW_FEES, f'is {dev_fees_perc}, should be {ids.NEW_FEES}'
        bounty_count_limit = load(context.mercenary_address, "bounty_count_limit", "felt")[0]
        assert bounty_count_limit == ids.NEW_BOUNTY_COUNT_LIMIT, f'is {bounty_count_limit}, should be {ids.NEW_BOUNTY_COUNT_LIMIT}'
        bounty_amount_limit_lords = load(context.mercenary_address, "bounty_amount_limit_lords", "Uint256")[0]
        assert bounty_amount_limit_lords == ids.NEW_AMOUNT_LIMIT_LORDS, f'is {bounty_amount_limit_lords}, should be {ids.NEW_AMOUNT_LIMIT_LORDS}'
        bounty_amount_limit_resources = load(context.mercenary_address, "bounty_amount_limit_resources", "Uint256", [1, 0])[0]
        assert bounty_amount_limit_resources == ids.NEW_AMOUNT_LIMIT_RESOURCES, f'is {bounty_amount_limit_resources}, should be {ids.NEW_AMOUNT_LIMIT_RESOURCES}'
        bounty_deadline_limit = load(context.mercenary_address, "bounty_deadline_limit", "felt")[0]
        assert bounty_deadline_limit == ids.NEW_DEADLINE_LIMIT, f'is {bounty_deadline_limit}, should be {ids.NEW_DEADLINE_LIMIT}'
    %}

    return ();
}

// verify that if not owner changes, it does not work
@external
func test_setter_not_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    ) {
    alloc_locals;
    local mercenary_address;
    %{
        ids.mercenary_address = context.mercenary_address
        start_prank(caller_address=1, target_contract_address=context.mercenary_address)
        expect_revert(error_message="Ownable: caller is not the owner")
    %}
    // test setters with != owner
    IMercenary.set_developer_fees_percentage(
        contract_address=mercenary_address, developer_fees_percentage_=1
    );

    return ();
}
