%lang starknet

// starkware
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_contract_address, get_block_number
from starkware.cairo.common.uint256 import Uint256

// contract
from contracts.mercenary import remove_bounty, clean_bounties

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
    local account2;
    local account3;
    let (self_address) = get_contract_address();
    %{
        ## deploy user accounts
        ## account1: bounty issuer
        ## account2: bounty issuer
        ## account3: bounty cleaner
        ## TODO: warning from __validate__deploy
        context.account1 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account1 = context.account1

        ## TODO: warning from __validate__deploy
        context.account2 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account2 = context.account2

        ## TODO: warning from __validate__deploy
        context.account3 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account3 = context.account3

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

        # construct events from here
        context.self_address = ids.self_address
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            if (i <= 4):
                # 5 times for account1
                # lords bounties
                bounty = [ids.account1, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0]
                store(context.self_address, "bounties", bounty, [ids.TARGET_REALM_ID, 0, i])
            if (i >=5 and i <= 9):
                # 5 times for account2
                # lords bounties
                bounty = [ids.account2, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0]
                store(context.self_address, "bounties", bounty, [ids.TARGET_REALM_ID, 0, i])
            if (i >= 10 and i < 40):
                # 30 resource bounties
                bounty = [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0]
                store(context.self_address, "bounties", bounty, [ids.TARGET_REALM_ID, 0, i])
            if (i>=40):
                # 10 times
                # resource bounties
                bounty = [ids.account2, ids.BOUNTY_AMOUNT, 0, 500, 0, 2, 0]
                store(context.self_address, "bounties", bounty, [ids.TARGET_REALM_ID, 0, i])

        # verify that the bounty at index 0 and index 12 is correct
        bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, 1])
        assert bounty == [ids.account1, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0]
        bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, 12])
        assert bounty == [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0]

        # add bounty_count_limit in storage
        store(context.self_address, "bounty_count", [ids.BOUNTY_COUNT_LIMIT], [ids.TARGET_REALM_ID, 0]) # 50 total bounties
        store(context.self_address, "bounty_count_limit", [ids.BOUNTY_COUNT_LIMIT])                     # 50 max bounties
        store(context.self_address, "cleaner_fees_percentage", [1000])                                  # 10% fees

        # put some erc1155 and erc20 tokens in bounty contract (this contract)
        # resources
        store(context.resources_contract, "ERC1155_balances", [100*ids.BOUNTY_AMOUNT], [1, 0, ids.self_address])
        store(context.resources_contract, "ERC1155_balances", [100*ids.BOUNTY_AMOUNT], [2, 0, ids.self_address])
        # lords
        store(context.lords_contract, "ERC20_balances", [100*ids.BOUNTY_AMOUNT], [ids.self_address])

        # define this contracts storage
        store(ids.self_address, "lords_contract", [context.lords_contract])
        store(ids.self_address, "erc1155_contract", [context.resources_contract])
    %}

    return ();
}

@external
func test_clean_with_no_expired_bounties{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> () {
    %{ stop_prank_callable = start_prank(caller_address=context.account3, target_contract_address=context.self_address) %}
    clean_bounties(Uint256(TARGET_REALM_ID, 0));
    %{
        # verify all bounties were removed
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, i])
            assert bounty != [0, 0, 0, 0, 0, 0, 0]

        # verify that account1 did not receive anything
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account1])[0]
        assert lords_amount == 0, f'should be {0} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account1])[0]
        assert resources1_amount == 0, f'should be {0} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account1])[0]
        assert resources2_amount == 0, f'should be {0} but is {resources2_amount}'

        # verify that account2 did not receive anything
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account2])[0]
        assert lords_amount == 0, f'should be {0} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account2])[0]
        assert resources1_amount == 0, f'should be {0} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account2])[0]
        assert resources2_amount == 0, f'should be {0} but is {resources2_amount}'

        # verify that account3 did not receive anything
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account3])[0]
        assert lords_amount == 0, f'should be {0} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account3])[0]
        assert resources1_amount == 0, f'should be {0} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account3])[0]
        assert resources2_amount == 0, f'should be {0} but is {resources2_amount}'


        # verify events
        expect_events(
        {"name": "BountiesCleaned", 
         "data": [ids.TARGET_REALM_ID, 0, 0]}
        )
    %}
    return ();
}

@external
func test_clean_with_some_expired_bounties{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> () {
    %{
        stop_roll = roll(500)
        stop_prank_callable = start_prank(caller_address=context.account3, target_contract_address=context.self_address)
    %}
    clean_bounties(Uint256(TARGET_REALM_ID, 0));
    %{
        # verify all bounties were removed
        for i in (0, ids.BOUNTY_COUNT_LIMIT):
            bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, i])
            if (i >= 10 and i < 40):
                assert bounty == [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0]
            else:
                assert bounty == [0, 0, 0, 0, 0, 0, 0]


        cleaner_bounty_amount = divmod(ids.BOUNTY_AMOUNT, 10)[0]
        owner_bounty_amount = ids.BOUNTY_AMOUNT - cleaner_bounty_amount

        # verify that account1 received back owner bounties
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account1])[0]
        # 5 expired lords bounties for account1
        assert lords_amount == 5*owner_bounty_amount, f'should be {5*owner_bounty_amount} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account1])[0]
        assert resources1_amount == 0, f'should be {0} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account1])[0]
        assert resources2_amount == 0, f'should be {0} but is {resources1_amount}'

        # verify that account2 received back owner amounts
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account2])[0]
        # 5 expired lords bounties for account2
        assert lords_amount == 5*owner_bounty_amount, f'should be {5*owner_bounty_amount} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account2])[0]
        assert resources1_amount == 0, f'should be {0} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account2])[0]
        # 10 expired resources2 bounties for account2
        assert resources2_amount == 10*owner_bounty_amount, f'should be {10*owner_bounty_amount} but is {resources2_amount}'

        # verify that account3 received back cleaner amounts
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account3])[0]
        # 10 expired lords bounties
        assert lords_amount == 10*cleaner_bounty_amount, f'should be {10*cleaner_bounty_amount} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account3])[0]
        assert resources1_amount == 0, f'should be {0} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account3])[0]
        # 10 expired resources bounties
        assert resources2_amount == 10*cleaner_bounty_amount, f'should be {10*cleaner_bounty_amount} but is {resources2_amount}'

        # construct event
        event_bounty1 = [item for i in range(0, 5) for item in [i, context.account1, owner_bounty_amount, 0, cleaner_bounty_amount, 0, 1, 0, 0]]
        event_bounty2 = [item for i in range(5, 10) for item in [i, context.account2, owner_bounty_amount, 0, cleaner_bounty_amount, 0, 1, 0, 0]]
        event_bounty4 = [item for i in range(40, 50) for item in  [i, context.account2, owner_bounty_amount, 0, cleaner_bounty_amount, 0, 0, 2, 0]]

        event = [ids.TARGET_REALM_ID, 0, 20] + event_bounty1 + event_bounty2 + event_bounty4 

        # verify events
        expect_events(
        {"name": "BountiesCleaned", 
         "data": event}
        )
    %}

    return ();
}

@external
func test_clean_with_all_expired_bounties{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> () {
    %{
        stop_roll = roll(1000)
        stop_prank_callable = start_prank(caller_address=context.account3, target_contract_address=context.self_address)
    %}
    clean_bounties(Uint256(TARGET_REALM_ID, 0));
    %{
        # verify all bounties were removed
        for i in (0, ids.BOUNTY_COUNT_LIMIT):
            bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 0, i])
            assert bounty == [0, 0, 0, 0, 0, 0, 0]

        cleaner_bounty_amount = divmod(ids.BOUNTY_AMOUNT, 10)[0]
        owner_bounty_amount = ids.BOUNTY_AMOUNT - cleaner_bounty_amount

        # verify that account1 received back owner bounties
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account1])[0]
        # 5 expired lords bounties for account1
        assert lords_amount == 5*owner_bounty_amount, f'should be {5*owner_bounty_amount} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account1])[0]
        # 30 resoure 2 bounties for account1
        assert resources1_amount == 30*owner_bounty_amount, f'should be {30*owner_bounty_amount} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account1])[0]
        assert resources2_amount == 0, f'should be {0} but is {resources1_amount}'

        # verify that account2 received back owner amounts
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account2])[0]
        # 5 expired lords bounties for account2
        assert lords_amount == 5*owner_bounty_amount, f'should be {5*owner_bounty_amount} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account2])[0]
        assert resources1_amount == 0, f'should be {0} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account2])[0]
        # 10 expired resources2 bounties for account2
        assert resources2_amount == 10*owner_bounty_amount, f'should be {10*owner_bounty_amount} but is {resources2_amount}'

        # verify that account3 received back cleaner amounts
        lords_amount = load(context.lords_contract, "ERC20_balances", "Uint256", [context.account3])[0]
        # 10 expired lords bounties
        assert lords_amount == 10*cleaner_bounty_amount, f'should be {10*cleaner_bounty_amount} but is {lords_amount}'
        resources1_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [1, 0, context.account3])[0]
        assert resources1_amount == 30*cleaner_bounty_amount, f'should be {0} but is {resources1_amount}'
        resources2_amount = load(context.resources_contract, "ERC1155_balances", "Uint256", [2, 0, context.account3])[0]
        # 10 expired resources bounties
        assert resources2_amount == 10*cleaner_bounty_amount, f'should be {10*cleaner_bounty_amount} but is {resources2_amount}'


        # construct event
        event_bounty1 = [item for i in range(0, 5) for item in [i, context.account1, owner_bounty_amount, 0, cleaner_bounty_amount, 0, 1, 0, 0]]
        event_bounty2 = [item for i in range(5, 10) for item in [i, context.account2, owner_bounty_amount, 0, cleaner_bounty_amount, 0, 1, 0, 0]]
        event_bounty3 = [item for i in range(10, 40) for item in [i, context.account1, owner_bounty_amount, 0, cleaner_bounty_amount, 0, 0, 1, 0]]
        event_bounty4 = [item for i in range(40, 50) for item in  [i, context.account2, owner_bounty_amount, 0, cleaner_bounty_amount, 0, 0, 2, 0]]

        event = [ids.TARGET_REALM_ID, 0, 50] + event_bounty1 + event_bounty2 + event_bounty3 + event_bounty4 

        # verify events
        expect_events(
        {"name": "BountiesCleaned", 
         "data": event}
        )
    %}

    return ();
}
