%lang starknet

// starkware
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_contract_address, call_contract
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

// mercenary
from contracts.IMercenary import IMercenary

// realms
from realms_contracts_git.contracts.settling_game.utils.game_structs import ExternalContractIds

const BOUNTY_COUNT_LIMIT = 5;
const BOUNTY_DEADLINE_LIMIT = 6;
const DEV_FEES_PERCENTAGE = 7;
const CLEANER_FEES_PERCENTAGE = 8;
const MODULE_CONTROLLER = 9;
const LORDS_DEV_FEES = 11 * 10 ** 18;
const RESOURCES_DEV_FEES_TOKEN1 = 4 * 10 ** 18;
const RESOURCES_DEV_FEES_TOKEN2 = 5 * 10 ** 18;
const RESOURCES_DEV_FEES_TOKEN3 = 6 * 10 ** 18;
const MINT_AMOUNT = 100 * 10 ** 18;

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    local proxy_address;
    let (self_address) = get_contract_address();
    // deploy the proxy contract
    %{
        import numpy as np
        lords_limit_amount = [10, 0]
        resources_amount = [10, 0]
        resource_len = token_ids_len = 4
        # token ids 1, 2, 3, 4
        token_ids = [1, 0, 2, 0, 3, 0, 4, 0]
        resources_amount_array = resource_len*resources_amount 
        mercenary_class_hash = declare("./contracts/Mercenary.cairo").class_hash
        ids.proxy_address = deploy_contract("./contracts/upgrade/Proxy.cairo",
                        [mercenary_class_hash,
                        # initializer
                        0x2dd76e7ad84dbed81c314ffe5e7a7cacfb8f4836f01af4e913f275f89a3de1a,
                        9 + len(lords_limit_amount) + len(resources_amount_array) + len(token_ids),
                        ids.self_address, 
                        ids.self_address, 
                        ids.MODULE_CONTROLLER,
                        ids.CLEANER_FEES_PERCENTAGE, 
                        ids.DEV_FEES_PERCENTAGE, 
                        ids.BOUNTY_COUNT_LIMIT,
                        *lords_limit_amount, 
                        ids.BOUNTY_DEADLINE_LIMIT,
                        resource_len, 
                        *resources_amount_array,
                        token_ids_len,
                        *token_ids]).contract_address
        context.proxy_address = ids.proxy_address
    %}
    // get storage values with view functions and assert
    // call view_cleaner_fees_percentage
    let (call_data: felt*) = alloc();
    let (_, cleaner_fees_perc) = call_contract(
        contract_address=proxy_address,
        function_selector=0x302066960f7dd70906d4c7028e22d1f5a5484876d0bce81f50bca6c2264fcd3,
        calldata_size=0,
        calldata=call_data,
    );
    assert cleaner_fees_perc[0] = CLEANER_FEES_PERCENTAGE;

    // call view_developer_fees_percentage
    let (call_data: felt*) = alloc();
    let (_, dev_fees_perc) = call_contract(
        contract_address=proxy_address,
        function_selector=0x36dab6167a954a592d8d491064b9d90542ecbe889d99ca5a3b235c54c85bfbd,
        calldata_size=0,
        calldata=call_data,
    );
    assert dev_fees_perc[0] = DEV_FEES_PERCENTAGE;

    // call view_bounty_count_limit
    let (_, bounty_count_limit) = call_contract(
        contract_address=proxy_address,
        function_selector=0x3154b2821f62b275fb75f86ad186de1047edc16f0f3608538c91ac348370530,
        calldata_size=0,
        calldata=call_data,
    );
    assert bounty_count_limit[0] = BOUNTY_COUNT_LIMIT;

    // call view_bounty_amount_limit_lords
    let (_, bounty_amount_limit_lords) = call_contract(
        contract_address=proxy_address,
        function_selector=0x28d5c806073a989e59881ddd45cd312a2cbf818941d71c500d206feb3aca545,
        calldata_size=0,
        calldata=call_data,
    );
    assert bounty_amount_limit_lords[0] = 10;

    // call view_bounty_amount_limit_resources
    let (resource_call_data: Uint256*) = alloc();
    assert resource_call_data[0] = Uint256(1, 0);
    let (_, bounty_amount_limit_resources) = call_contract(
        contract_address=proxy_address,
        function_selector=0x2b3237777ec9cf4b50e9c5444a43c631bd5be8df1f813b1563eafa8dd578529,
        calldata_size=2,
        calldata=resource_call_data,
    );
    assert bounty_amount_limit_resources[0] = 10;

    // call view_bounty_deadline_limit
    let (_, bounty_deadline_limit) = call_contract(
        contract_address=proxy_address,
        function_selector=0x38ab7f0528a3dc2f10d4322775b9a666a22ff2a2173bcd5c86de3cebc42d1e,
        calldata_size=0,
        calldata=call_data,
    );
    assert bounty_deadline_limit[0] = BOUNTY_DEADLINE_LIMIT;

    // verify that the values are the correct ones in the storage directly
    %{
        ## check that the bounty_amount_limit_resources storage was correctly filled
        for i in range(0, 4):
            if (i%2 == 0):
                resource_amount = load(ids.proxy_address, "bounty_amount_limit_resources", "felt", [token_ids[i], token_ids[i+1]])
                resource_amount_true = [resources_amount_array[i]]
                assert resource_amount == resource_amount_true, f'resource amount in contract is {resource_amount} while should be {resource_amount_true}'

        # values not accessible through getters
        ## retrieve
        owner = load(ids.proxy_address, "Ownable_owner", "felt")[0]
        proxy_admin = load(ids.proxy_address, "Proxy_admin", "felt")[0]
        ## compare
        assert owner == ids.self_address, f'owner error, expected {ids.self_address}, got {owner}'
        assert proxy_admin == ids.self_address, f'proxy admin error, expected {ids.self_address}, got {proxy_admin}'
    %}
    return ();
}

@external
func test_upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    alloc_locals;
    local proxy_address;
    local upgraded_mercenary_class_hash;
    // declare mock up upgraded mercenary contract with function
    // to increase bounty_count_limit by 1
    %{
        ids.proxy_address = context.proxy_address 
        ids.upgraded_mercenary_class_hash = declare("./tests/contracts/UpgradedMercenary.cairo").class_hash
    %}

    // upgrade
    let (call_data: felt*) = alloc();
    assert call_data[0] = upgraded_mercenary_class_hash;
    call_contract(
        contract_address=proxy_address,
        function_selector=0xf2f7c15cbe06c8d94597cd91fd7f3369eae842359235712def5584f8d270cd,
        calldata_size=1,
        calldata=call_data,
    );

    // new function in upgraded contract: increase_bounty_count_limit
    let (call_data: felt*) = alloc();
    call_contract(
        contract_address=proxy_address,
        function_selector=0x200b659f69ac6007260878ae788dad36411804a956121e9266174f5a186eee2,
        calldata_size=0,
        calldata=call_data,
    );

    // verify that storage changed
    %{
        bounty_count_limit = load(context.proxy_address, "bounty_count_limit", "felt")[0] 
        assert bounty_count_limit == ids.BOUNTY_COUNT_LIMIT + 1, f'is {bounty_count_limit}, should be {ids.BOUNTY_COUNT_LIMIT + 1}'
    %}

    return ();
}

@external
func test_setters{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    alloc_locals;

    local proxy_address;

    const NEW_CLEANER_FEES = 900;
    const NEW_DEV_FEES = 1000;
    const NEW_BOUNTY_COUNT_LIMIT = 1100;
    const NEW_AMOUNT_LIMIT_LORDS = 1200;
    const NEW_AMOUNT_LIMIT_RESOURCES = 1300;
    const NEW_DEADLINE_LIMIT = 1400;

    %{ ids.proxy_address = context.proxy_address %}

    // test setters

    // set_cleaner_fees_percentage
    let (call_data: felt*) = alloc();
    assert call_data[0] = NEW_CLEANER_FEES;
    call_contract(
        contract_address=proxy_address,
        function_selector=0x1e828979d2cecd4341475de8aee4e05bfbf95b70ece675101dc124b65cc3b67,
        calldata_size=1,
        calldata=call_data,
    );

    // set_developer_fees_percentage
    let (call_data: felt*) = alloc();
    assert call_data[0] = NEW_DEV_FEES;
    call_contract(
        contract_address=proxy_address,
        function_selector=0x26f4cbfeb21a08888ac4c195eb79e1f7b66ac9252f18a2523a4a63538a8673a,
        calldata_size=1,
        calldata=call_data,
    );

    // set_bounty_count_limit
    let (call_data: felt*) = alloc();
    assert call_data[0] = NEW_BOUNTY_COUNT_LIMIT;
    call_contract(
        contract_address=proxy_address,
        function_selector=0x186bfbbc847e8d2f7b50e495cd17ac0b9ea5436038131d0d8208b0f6ea0d85d,
        calldata_size=1,
        calldata=call_data,
    );

    // set_bounty_amount_limit_lords
    let (uint_call_data: Uint256*) = alloc();
    assert uint_call_data[0] = Uint256(NEW_AMOUNT_LIMIT_LORDS, 0);
    call_contract(
        contract_address=proxy_address,
        function_selector=0x2c2c5a10dbe60ab8fd0adbd19f7d08bc42a8107b50b746cb42a1cb31876f9e3,
        calldata_size=2,
        calldata=uint_call_data,
    );

    // set_bounty_amount_limit_resources
    let (uint_call_data: Uint256*) = alloc();
    assert uint_call_data[0] = Uint256(1, 0);
    assert uint_call_data[1] = Uint256(NEW_AMOUNT_LIMIT_RESOURCES, 0);
    call_contract(
        contract_address=proxy_address,
        function_selector=0x26641f39f869a4be5c0fb2cb03750f3022f619389119120a73264d16fe83051,
        calldata_size=4,
        calldata=uint_call_data,
    );

    // set_bounty_deadline_limit
    let (call_data: felt*) = alloc();
    assert call_data[0] = NEW_DEADLINE_LIMIT;

    call_contract(
        contract_address=proxy_address,
        function_selector=0x3508e72f6bf5cced441c0ca064e60c6bf4e3e7423fa69c9538f80288d3fbda4,
        calldata_size=1,
        calldata=call_data,
    );

    // verify storage changed
    %{
        cleaner_fees_perc = load(context.proxy_address, "cleaner_fees_percentage", "felt")[0]
        assert cleaner_fees_perc == ids.NEW_CLEANER_FEES, f'is {cleaner_fees_perc}, should be {ids.NEW_CLEANER_FEES}'
        dev_fees_perc = load(context.proxy_address, "developer_fees_percentage", "felt")[0]
        assert dev_fees_perc == ids.NEW_DEV_FEES, f'is {dev_fees_perc}, should be {ids.NEW_DEV_FEES}'
        bounty_count_limit = load(context.proxy_address, "bounty_count_limit", "felt")[0]
        assert bounty_count_limit == ids.NEW_BOUNTY_COUNT_LIMIT, f'is {bounty_count_limit}, should be {ids.NEW_BOUNTY_COUNT_LIMIT}'
        bounty_amount_limit_lords = load(context.proxy_address, "bounty_amount_limit_lords", "felt")[0]
        assert bounty_amount_limit_lords == ids.NEW_AMOUNT_LIMIT_LORDS, f'is {bounty_amount_limit_lords}, should be {ids.NEW_AMOUNT_LIMIT_LORDS}'
        bounty_amount_limit_resources = load(context.proxy_address, "bounty_amount_limit_resources", "felt", [1, 0])[0]
        assert bounty_amount_limit_resources == ids.NEW_AMOUNT_LIMIT_RESOURCES, f'is {bounty_amount_limit_resources}, should be {ids.NEW_AMOUNT_LIMIT_RESOURCES}'
        bounty_deadline_limit = load(context.proxy_address, "bounty_deadline_limit", "felt")[0]
        assert bounty_deadline_limit == ids.NEW_DEADLINE_LIMIT, f'is {bounty_deadline_limit}, should be {ids.NEW_DEADLINE_LIMIT}'
    %}

    return ();
}

// verify that if not owner changes, it reverts
@external
func test_setter_not_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    ) {
    alloc_locals;
    local proxy_address;
    %{
        ids.proxy_address = context.proxy_address
        start_prank(caller_address=1, target_contract_address=context.proxy_address)
        expect_revert(error_message="Ownable: caller is not the owner")
    %}
    // test setters with != owner
    // set_developer_fees_percentage
    let (call_data: felt*) = alloc();
    assert call_data[0] = 1;
    call_contract(
        contract_address=proxy_address,
        function_selector=0x26f4cbfeb21a08888ac4c195eb79e1f7b66ac9252f18a2523a4a63538a8673a,
        calldata_size=1,
        calldata=call_data,
    );

    return ();
}

@external
func test_send_back_dev_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    ) {
    alloc_locals;
    local account1;
    let (self_address) = get_contract_address();
    local proxy_address;
    %{
        ids.proxy_address = context.proxy_address
        ## deploy user account
        ## TODO: warning from __validate__deploy
        context.account1 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account1 = context.account1

        ## deploy resources contract
        context.resources_contract = deploy_contract("lib/realms_contracts_git/contracts/token/ERC1155_Mintable_Burnable.cairo").contract_address

        ## deploy lords contract
        context.lords_contract = deploy_contract("lib/cairo_contracts_git/src/openzeppelin/token/erc20/presets/ERC20Mintable.cairo", \
        [0, 0, 6, ids.MINT_AMOUNT, 0, ids.self_address, ids.self_address]).contract_address

        ## deploy modules controller contract and setup external contract and modules ids
        context.mc_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/ModuleController.cairo").contract_address
        # store in module controller
        store(context.mc_contract, "external_contract_table", [context.resources_contract], [ids.ExternalContractIds.Resources])
        store(context.mc_contract, "external_contract_table", [context.lords_contract], [ids.ExternalContractIds.Lords])
        # store in mercenary contract
        store(ids.proxy_address, "module_controller_address", [context.mc_contract])

        ## store amounts in dev fees storage
        # lords
        store(ids.proxy_address, "dev_fees_lords", [ids.LORDS_DEV_FEES])

        # resources
        store(ids.proxy_address, "dev_fees_resources", [ids.RESOURCES_DEV_FEES_TOKEN1, 0], [1, 0])
        store(ids.proxy_address, "dev_fees_resources", [ids.RESOURCES_DEV_FEES_TOKEN2, 0], [2, 0])
        store(ids.proxy_address, "dev_fees_resources", [ids.RESOURCES_DEV_FEES_TOKEN3, 0], [3, 0])

        ## mint some resources and lords for mercenary contract
        #directly change in the storage the amounts
        store(context.lords_contract, "ERC20_balances", [ids.MINT_AMOUNT], [context.proxy_address])
        store(context.resources_contract, "ERC1155_balances", [ids.MINT_AMOUNT], [1, 0, context.proxy_address])
        store(context.resources_contract, "ERC1155_balances", [ids.MINT_AMOUNT], [2, 0, context.proxy_address])
        store(context.resources_contract, "ERC1155_balances", [ids.MINT_AMOUNT], [3, 0, context.proxy_address])
    %}

    let (resources_ids: Uint256*) = alloc();
    assert resources_ids[0] = Uint256(1, 0);
    assert resources_ids[1] = Uint256(2, 0);
    assert resources_ids[2] = Uint256(3, 0);

    // test function that sends the dev fees
    // transfer_dev_fees
    let (call_data: felt*) = alloc();
    assert call_data[0] = account1;
    assert call_data[1] = 3;
    assert call_data[2] = 1;
    assert call_data[3] = 0;
    assert call_data[4] = 2;
    assert call_data[5] = 0;
    assert call_data[6] = 3;
    assert call_data[7] = 0;

    // calling transfer_dev_fees
    call_contract(
        contract_address=proxy_address,
        function_selector=0x67f35a4f552409d1423a365bb1f87844a7ced936b69488e4d86ac92fa9edb1,
        calldata_size=8,
        calldata=call_data,
    );

    // verify balance of account1
    %{
        # lords
        balance_lords = load(context.lords_contract, "ERC20_balances", "Uint256", [ids.account1])[0]
        # resources
        balance_resources1 = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, ids.account1])[0]
        balance_resources2 = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, ids.account1])[0]
        balance_resources3 = load(context.resources_contract, "ERC1155_balances", "Uint256", [3, 0, ids.account1])[0]

        assert balance_lords == ids.LORDS_DEV_FEES
        assert balance_resources1 == ids.RESOURCES_DEV_FEES_TOKEN1
        assert balance_resources2 == ids.RESOURCES_DEV_FEES_TOKEN2
        assert balance_resources3 == ids.RESOURCES_DEV_FEES_TOKEN3
    %}

    // verify event
    %{
        expect_events(
                {"name": "DevFeesTransferred", 
                 "data": [
                 context.account1, ids.LORDS_DEV_FEES, 0, 
                 # resources ids
                 3, 1, 0, 2, 0, 3, 0, 
                 # resources amounts
                 3, ids.RESOURCES_DEV_FEES_TOKEN1, 0, ids.RESOURCES_DEV_FEES_TOKEN2, 0, ids.RESOURCES_DEV_FEES_TOKEN3, 0]}
                )
    %}

    return ();
}
