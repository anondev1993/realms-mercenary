%lang starknet
// starkware
from starkware.cairo.common.uint256 import Uint256, assert_uint256_eq
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)
from starkware.cairo.common.alloc import alloc

// mercenary
from contracts.mercenary import issue_bounty, onERC1155Received
from contracts.library import MercenaryLib
from contracts.storage import supportsInterface, bounties
from contracts.structures import Bounty, BountyType
from contracts.constants import DEVELOPER_FEES_PRECISION

// realms
from realms_contracts_git.contracts.settling_game.utils.game_structs import (
    ModuleIds,
    ExternalContractIds,
)

// fee percentage = 9.99%
const FEE_PERCENTAGE = 999;
const MINT_AMOUNT = 100 * 10 ** 18;
const REALM_CONTRACT = 121;
const S_REALM_CONTRACT = 122;
const COMBAT_MODULE = 123;
const BOUNTY_ISSUER = 124;
const BOUNTY_AMOUNT = 5 * 10 ** 18;
const TARGET_REALM_ID = 125;
const BOUNTY_COUNT_LIMIT = 50;
const BOUNTY_DEADLINE_LIMIT = 100;

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    // setup all the bounties (some lords, some resources)
    alloc_locals;
    let (self_address) = get_contract_address();
    local lords_contract;
    local resources_contract;
    local account1;
    local mc_contract;
    %{
        context.self_address = ids.self_address
        ## deploy lords and resources contract
        context.lords_contract = deploy_contract("lib/cairo_contracts_git/src/openzeppelin/token/erc20/presets/ERC20Mintable.cairo",
         [0, 0, 6, ids.MINT_AMOUNT, 0, ids.self_address, ids.self_address]).contract_address
        ids.lords_contract = context.lords_contract
        context.resources_contract = deploy_contract("lib/realms_contracts_git/contracts/token/ERC1155_Mintable_Burnable.cairo").contract_address
        ids.resources_contract = context.resources_contract

        ## deploy user accounts
        context.account1 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account1 = context.account1

        ## deploy modules controller contract and setup external contract and modules ids
        context.mc_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/ModuleController.cairo").contract_address
        ids.mc_contract = context.mc_contract
        # store in module controller
        store(context.mc_contract, "external_contract_table", [context.resources_contract], [ids.ExternalContractIds.Resources])
        store(context.mc_contract, "external_contract_table", [context.lords_contract], [ids.ExternalContractIds.Lords])

        # store in local contract
        store(context.self_address, "module_controller_address", [context.mc_contract])
        store(context.self_address, "bounty_deadline_limit", [ids.BOUNTY_DEADLINE_LIMIT])

        ## set developer fees to 10%
        store(context.self_address, "developer_fees_percentage", [ids.FEE_PERCENTAGE])

        ## create bounties in storage
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            if (i <= 9):
                # 10 times
                # lords bounties
                store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0], [ids.TARGET_REALM_ID, 0, i])
            if (i >= 10 and i < 40):
                # 30 times
                # resource bounties
                store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0], [ids.TARGET_REALM_ID, 0, i])
            if (i>=40):
                # 10 times
                # resource bounties
                store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 1, 0, 0], [ids.TARGET_REALM_ID, 0, i])

        ## mint some resources
        store(context.resources_contract, "ERC1155_balances", [100*ids.BOUNTY_AMOUNT], [1, 0, context.self_address])
    %}

    with_attr error_message("bounty at index 0 not initialized") {
        let (bounty) = bounties.read(Uint256(TARGET_REALM_ID, 0), 0);
        assert_uint256_eq(bounty.amount, Uint256(BOUNTY_AMOUNT, 0));
    }

    return ();
}

// @dev Verifies that the lords are correctly summed up between attacker and dev
// @dev and that the bounties are reset at the same time
@external
func test_collect_lords_without_expired_bounties{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() {
    alloc_locals;
    %{ stop_prank_callable = start_prank(context.account1, context.self_address) %}
    let (local attacker_amount) = MercenaryLib.collect_lords(
        Uint256(TARGET_REALM_ID, 0), BOUNTY_COUNT_LIMIT, FEE_PERCENTAGE
    );
    %{ stop_prank_callable() %}

    // verify the lords amounts between attacker and dev
    %{
        sum_lords = 20*ids.BOUNTY_AMOUNT
        dev_lords = sum_lords * ids.FEE_PERCENTAGE
        (dev_lords, _)  = divmod(dev_lords, ids.DEVELOPER_FEES_PRECISION)
        attacker_lords = sum_lords - dev_lords
        storage_dev_fees = load(context.self_address, "dev_fees_lords", "Uint256")[0]

        ## assert that python and cairo results are similar
        assert dev_lords == storage_dev_fees
        assert reflect(ids).attacker_amount.get().low == attacker_lords
    %}

    // verify that the account1 did not have any transfer of lord or resources
    // from expired bounties
    %{
        lords_balance = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account1])[0]
        assert lords_balance == 0, f'should be 0, is {lords_balance}'
        resources_1_balance = load(context.lords_contract, "ERC1155_balances", "Uint256", [1, 0, context.account1])[0]
        assert resources_1_balance == 0, f'should be 0, is {resources_1_balance}'
    %}

    return ();
}

// @dev Verifies that the lords are correctly summed up between attacker and dev
// @dev and that the bounties are reset at the same time
@external
func test_collect_lords_with_expired_bounties{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() {
    alloc_locals;

    %{
        # go into the future to make all bounties expired
        stop_warp = roll(1001)
        stop_prank_callable = start_prank(context.account1, context.self_address)
    %}
    let (local attacker_amount) = MercenaryLib.collect_lords(
        Uint256(TARGET_REALM_ID, 0), BOUNTY_COUNT_LIMIT, FEE_PERCENTAGE
    );
    %{ stop_prank_callable() %}

    // verify the lords amounts between attacker and dev
    %{
        storage_dev_fees = load(context.self_address, "dev_fees_lords", "Uint256")[0]
        assert storage_dev_fees == 0, f'should be 0, is {storage_dev_fees}'
        attacker_amount = reflect(ids).attacker_amount.get().low
        assert attacker_amount == 0, f'should be 0, is {attacker_amount}'
    %}

    // verify that the account1 did not have any transfer of lord or resources
    // from expired bounties
    %{
        lords_balance = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account1])[0]
        assert lords_balance == 20*ids.BOUNTY_AMOUNT, f'should be {20*ids.BOUNTY_AMOUNT}, is {lords_balance}'
        resources_1_balance = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account1])[0]
        assert resources_1_balance == 30*ids.BOUNTY_AMOUNT, f'should be {30*ids.BOUNTY_AMOUNT}, is {resources_1_balance}'
    %}

    return ();
}

// @dev Verifies that the resources are correctly summed up between attacker and dev
// @dev and that the bounties are reset at the same time
@external
func test_collect_resources{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    ) {
    alloc_locals;
    // cairo calculations
    let (local resources_ids: Uint256*) = alloc();
    let (local attacker_resources_amounts: Uint256*) = alloc();
    let (local dev_resources_amounts: Uint256*) = alloc();

    // quick check for random bounty
    with_attr error_message("bounty 12 not initialized") {
        let (bounty) = bounties.read(Uint256(TARGET_REALM_ID, 0), 12);
        assert_uint256_eq(bounty.amount, Uint256(BOUNTY_AMOUNT, 0));
    }

    let ids_len = MercenaryLib.collect_resources(
        resources_ids,
        attacker_resources_amounts,
        dev_resources_amounts,
        Uint256(TARGET_REALM_ID, 0),
        0,
        0,
        BOUNTY_COUNT_LIMIT,
        FEE_PERCENTAGE,
    );

    // get felt pointers to retrieve from memory in python hint
    local ptr_attacker_resources_amounts: felt* = cast(attacker_resources_amounts, felt*);
    local ptr_resources_ids: felt* = cast(resources_ids, felt*);

    %{
        # total resources amount going to devs
        python_dev_resources_amounts = 0
        # list of amounts going to the attacker
        python_attacker_resources_amounts = []
        for i in range(0, 2*ids.ids_len, 2):
            # amounts
            dev_fees = ids.BOUNTY_AMOUNT * ids.FEE_PERCENTAGE
            (dev_fees, _)  = divmod(dev_fees, ids.DEVELOPER_FEES_PRECISION)
            assert memory[ids.ptr_attacker_resources_amounts + i] == ids.BOUNTY_AMOUNT - dev_fees
            assert memory[ids.ptr_attacker_resources_amounts + i + 1] == 0
            python_dev_resources_amounts+=dev_fees

            # token ids
            assert memory[ids.ptr_resources_ids + i] == 1
            assert memory[ids.ptr_resources_ids + i + 1] == 0

        ## assert that the sum of devs amounts for token Id 1, 0 is correct
        dev_resources_amounts = load(context.self_address, "dev_fees_resources", "Uint256", [1,0])[0]
        assert python_dev_resources_amounts == dev_resources_amounts

        ## assert resources bounties resets
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, i])
            # if bounty is resources bounty
            if bounty[4] != 1:
                assert bounty == 7*[0]
    %}

    with_attr error_message("wrong ids_len") {
        assert ids_len = 30;
    }

    return ();
}
