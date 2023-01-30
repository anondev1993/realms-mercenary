%lang starknet

// starkware
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_contract_address
from starkware.cairo.common.uint256 import Uint256

// contract
from contracts.mercenary import remove_bounty

// realms
from realms_contracts_git.contracts.settling_game.utils.game_structs import ExternalContractIds

const MINT_AMOUNT = 0;
const BOUNTY_AMOUNT = 5 * 10 ** 18;
const TARGET_REALM_ID = 125;
const BOUNTY_COUNT_LIMIT = 50;

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    // setup bounties in mercenary contract
    alloc_locals;
    local account1;
    let (self_address) = get_contract_address();
    %{
        ## deploy user accounts
        ## TODO: warning from __validate__deploy
        context.account1 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account1 = context.account1

        ## deploy resources contract
        context.resources_contract = deploy_contract("lib/realms_contracts_git/contracts/token/ERC1155_Mintable_Burnable.cairo").contract_address

        ## deploy lords contract
        context.lords_contract = deploy_contract("lib/cairo_contracts_git/src/openzeppelin/token/erc20/presets/ERC20Mintable.cairo", [0, 0, 6, ids.MINT_AMOUNT, 0, ids.self_address, ids.self_address]).contract_address

        ## deploy modules controller contract and setup external contract and modules ids
        context.mc_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/ModuleController.cairo").contract_address
        # store in module controller
        store(context.mc_contract, "external_contract_table", [context.resources_contract], [ids.ExternalContractIds.Resources])
        store(context.mc_contract, "external_contract_table", [context.lords_contract], [ids.ExternalContractIds.Lords])

        # store in local contract
        store(ids.self_address, "module_controller_address", [context.mc_contract])

        context.self_address = ids.self_address
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            if (i <= 9):
                # 10 times
                # lords bounties
                store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0], [ids.TARGET_REALM_ID, 0, i])
            if (i >= 10 and i < 40):
                # 30 resource bounties
                store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0], [ids.TARGET_REALM_ID, 0, i])
            if (i>=40):
                # 10 times
                # resource bounties
                store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 0, 2, 0], [ids.TARGET_REALM_ID, 0, i])

        # verify that the bounty at index 0 and index 12is correct
        bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, 1])
        assert bounty == [ids.account1, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0]
        bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, 12])
        assert bounty == [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0]

        # put some erc1155 and erc20 tokens in bounty contract (this contract)
        # resources
        store(context.resources_contract, "ERC1155_balances", [ids.BOUNTY_AMOUNT], [1, 0, ids.self_address])
        store(context.resources_contract, "ERC1155_balances", [ids.BOUNTY_AMOUNT], [2, 0, ids.self_address])
        # lords
        store(context.lords_contract, "ERC20_balances", [ids.BOUNTY_AMOUNT], [ids.self_address])

        # define this contracts storage
        store(ids.self_address, "lords_contract", [context.lords_contract])
        store(ids.self_address, "erc1155_contract", [context.resources_contract])
    %}

    return ();
}

@external
func test_remove_lords_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> () {
    alloc_locals;
    %{
        # get the bounty before removing it 
        old_bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, 1])
        stop_prank_callable = start_prank(caller_address=context.account1, target_contract_address=context.self_address)
    %}
    remove_bounty(1, Uint256(TARGET_REALM_ID, 0));
    %{ stop_prank_callable() %}
    %{
        # verify that the bounty is removed after claim
        new_bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, 1])
        assert new_bounty == [0, 0, 0, 0, 0, 0, 0]

        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account1])
        assert lords_amount[0] == ids.BOUNTY_AMOUNT, f'lords amount of person who removed bounty should be {ids.BOUNTY_AMOUNT} but is {lords_amount[0]}'
    %}

    %{
        # verify event
        event = old_bounty + [ids.TARGET_REALM_ID, 0, 1] 
        expect_events(
        {"name": "BountyRemoved", 
        "data": event}
        )
    %}

    return ();
}

@external
func test_remove_resources_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> () {
    alloc_locals;
    %{
        # get the bounty before removing it 
        old_bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, 12])
        stop_prank_callable = start_prank(caller_address=context.account1, target_contract_address=context.self_address)
    %}
    // remove the bounty at index 12
    remove_bounty(12, Uint256(TARGET_REALM_ID, 0));
    %{ stop_prank_callable() %}
    %{
        # verify that the bounty is removed after claim
        new_bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, 12])
        assert new_bounty == [0, 0, 0, 0, 0, 0, 0]

        # verify that the account1 received the new tokens
        resources_amount = load(context.resources_contract, "ERC1155_balances", "felt", [1, 0, context.account1]) 
        assert resources_amount[0] == ids.BOUNTY_AMOUNT, f'resources amount for token id 1 should be {ids.BOUNTY_AMOUNT} but is {resources_amount}'
    %}

    %{
        # verify event
        event = old_bounty + [ids.TARGET_REALM_ID, 0, 12] 
        expect_events(
        {"name": "BountyRemoved", 
        "data": event}
        )
    %}

    return ();
}
