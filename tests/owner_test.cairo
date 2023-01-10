%lang starknet

// starkware
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_contract_address
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

// mercenary
from contracts.interface import IMercenary

// realms
from realms_contracts_git.contracts.settling_game.utils.game_structs import (
    ModuleIds,
    ExternalContractIds,
)

const RESOURCE_CONTRACT = 1;
const BOUNTY_COUNT_LIMIT = 6;
const BOUNTY_DEADLINE_LIMIT = 7;
const DEV_FEES_PERCENTAGE = 8;
const MODULE_CONTROLLER = 9;
const LORDS_DEV_FEES = 11 * 10 ** 18;
const RESOURCES_DEV_FEES_TOKEN1 = 4 * 10 ** 18;
const RESOURCES_DEV_FEES_TOKEN2 = 5 * 10 ** 18;
const RESOURCES_DEV_FEES_TOKEN3 = 6 * 10 ** 18;
const MINT_AMOUNT = 100 * 10 ** 18;

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
                        ids.MODULE_CONTROLLER,
                        ids.DEV_FEES_PERCENTAGE, 
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

        ## compare
        assert owner == ids.self_address, f'owner error, expected {ids.self_address}, got {owner}'

        # values retrieved through getters
        ## compare
        assert ids.dev_fees_perc == ids.DEV_FEES_PERCENTAGE, f'dev fees error, exepcted {ids.DEV_FEES_PERCENTAGE}, got {dev_fees_perc}'
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

@external
func test_send_back_dev_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    ) {
    alloc_locals;
    local account1;
    let (self_address) = get_contract_address();
    local mercenary_address;
    %{
        ids.mercenary_address = context.mercenary_address
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
        store(ids.mercenary_address, "module_controller_address", [context.mc_contract])

        ## store amounts in dev fees storage
        # lords
        store(ids.mercenary_address, "dev_fees_lords", [ids.LORDS_DEV_FEES])

        # resources
        store(ids.mercenary_address, "dev_fees_resources", [ids.RESOURCES_DEV_FEES_TOKEN1, 0], [1, 0])
        store(ids.mercenary_address, "dev_fees_resources", [ids.RESOURCES_DEV_FEES_TOKEN2, 0], [2, 0])
        store(ids.mercenary_address, "dev_fees_resources", [ids.RESOURCES_DEV_FEES_TOKEN3, 0], [3, 0])

        ## mint some resources and lords for mercenary contract
        #directly change in the storage the amounts
        store(context.lords_contract, "ERC20_balances", [ids.MINT_AMOUNT], [context.mercenary_address])
        store(context.resources_contract, "ERC1155_balances", [ids.MINT_AMOUNT], [1, 0, context.mercenary_address])
        store(context.resources_contract, "ERC1155_balances", [ids.MINT_AMOUNT], [2, 0, context.mercenary_address])
        store(context.resources_contract, "ERC1155_balances", [ids.MINT_AMOUNT], [3, 0, context.mercenary_address])
    %}

    let (resources_ids: Uint256*) = alloc();
    assert resources_ids[0] = Uint256(1, 0);
    assert resources_ids[1] = Uint256(2, 0);
    assert resources_ids[2] = Uint256(3, 0);

    // test function that sends the dev fees
    IMercenary.transfer_dev_fees(mercenary_address, account1, 3, resources_ids);

    // verify balance of accoun1
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

    return ();
}
