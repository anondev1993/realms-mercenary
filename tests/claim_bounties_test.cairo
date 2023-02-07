%lang starknet

// starkware
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_contract_address

// mercenary
from contracts.mercenary import onERC1155BatchReceived, claim_bounties
from contracts.storage import supportsInterface
from contracts.structures import Bounty, BountyType, PackedBounty

// realms
from realms_contracts_git.contracts.settling_game.utils.game_structs import (
    ModuleIds,
    ExternalContractIds,
)

@contract_interface
namespace IRealms {
    func initializer(name: felt, symbol: felt, proxy_admin: felt) {
    }
    func mint(to: felt, tokenId: Uint256) {
    }
    func set_realm_data(tokenId: Uint256, _realm_name: felt, _realm_data: felt) {
    }
}

@contract_interface
namespace ISRealms {
    func initializer(name: felt, symbol: felt, proxy_admin: felt, module_controller_address: felt) {
    }
    func approve(to: felt, tokenId: Uint256) {
    }
    func mint(to: felt, tokenId: Uint256) {
    }
}

const MINT_AMOUNT = 100 * 10 ** 18;
const BOUNTY_AMOUNT = 5 * 10 ** 18;
const TARGET_REALM_ID = 125;
const ATTACKING_REALM_ID = 126;
const ATTACKING_ARMY_ID = 127;
const DEFENDING_ARMY_ID = 129;
const BOUNTY_COUNT_LIMIT = 50;

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    let (address) = get_contract_address();
    local resources_contract;
    local lords_contract;
    local realms_contract;
    local s_realms_contract;
    local mc_contract;
    local combat_contract;
    local account1;
    local account2;

    %{
        # import the unpack, pack functions
        import sys
        sys.path.insert(0,'tests')
        from utils import pack_bounty_info, unpack_bounty_info
        context.pack_bounty_info = pack_bounty_info
        context.unpack_bounty_info = unpack_bounty_info
    %}

    %{
        context.self_address = ids.address

        ## deploy lords contract
        context.lords_contract = deploy_contract("lib/cairo_contracts_git/src/openzeppelin/token/erc20/presets/ERC20Mintable.cairo",
         [0, 0, 6, ids.MINT_AMOUNT, 0, ids.address, ids.address]).contract_address
        ids.lords_contract = context.lords_contract
        ## verify that the mint amount went to current contract
        lords_amount = load(ids.lords_contract, "ERC20_balances", "Uint256", [context.self_address])
        assert lords_amount[0] == ids.MINT_AMOUNT, f'lords amount in contract should be {100*10**18} but is {lords_amount}'

        ## deploy resources contract
        context.resources_contract = deploy_contract("lib/realms_contracts_git/contracts/token/ERC1155_Mintable_Burnable.cairo").contract_address
        ids.resources_contract = context.resources_contract

        ## deploy user accounts
        ## TODO: warning from __validate__deploy
        context.account1 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account1 = context.account1
        context.account2 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account2 = context.account2

        ## deploy combat module
        ids.combat_contract = deploy_contract("tests/contracts/Combat.cairo", [1, context.resources_contract]).contract_address
        context.combat_contract = ids.combat_contract

        ## deploy realms nft contract
        ids.realms_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/tokens/Realms_ERC721_Mintable.cairo").contract_address
        context.realms_contract = ids.realms_contract

        ## deploy staked realms nft contract
        ids.s_realms_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/tokens/S_Realms_ERC721_Mintable.cairo").contract_address
        context.s_realms_contract = ids.s_realms_contract

        ## deploy modules controller contract and setup external contract and modules ids
        context.mc_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/ModuleController.cairo").contract_address
        ids.mc_contract = context.mc_contract
        # store in module controller
        store(context.mc_contract, "external_contract_table", [context.resources_contract], [ids.ExternalContractIds.Resources])
        store(context.mc_contract, "external_contract_table", [context.lords_contract], [ids.ExternalContractIds.Lords])
        store(context.mc_contract, "external_contract_table", [context.s_realms_contract], [ids.ExternalContractIds.S_Realms])
        store(context.mc_contract, "external_contract_table", [context.realms_contract], [ids.ExternalContractIds.Realms])
        store(context.mc_contract, "address_of_module_id", [context.combat_contract], [ids.ModuleIds.L06_Combat])

        # store in local contract
        store(context.self_address, "module_controller_address", [context.mc_contract])


        ## set local storage vars
        store(context.self_address, "bounty_count_limit", [ids.BOUNTY_COUNT_LIMIT])
        store(context.self_address, "developer_fees_percentage", [1000])                               # 10% fees

        ## module controller storage
        store(context.mc_contract, "module_id_of_address", [1], [context.self_address])
        store(context.mc_contract, "address_of_module_id", [context.self_address], [1])
        store(context.mc_contract, "module_id_of_address", [2], [context.s_realms_contract])
        store(context.mc_contract, "address_of_module_id", [context.s_realms_contract], [2])
        store(context.mc_contract, "can_write_to", [1], [1, 2])
    %}

    //
    // ATTACKER
    //
    // mint staked realm for account 1 (attacking) and approve to mercenary contract
    ISRealms.initializer(s_realms_contract, 0, 0, address, mc_contract);
    // mint realms
    ISRealms.mint(s_realms_contract, account1, Uint256(ATTACKING_REALM_ID, 0));
    // approve to mercenary contract
    %{ stop_prank_callable = start_prank(caller_address=ids.account1, target_contract_address=ids.s_realms_contract) %}
    ISRealms.approve(s_realms_contract, address, Uint256(ATTACKING_REALM_ID, 0));
    %{ stop_prank_callable() %}

    //
    // DEFENDER
    //
    // mint realm for account 2 (defending) and set data
    IRealms.initializer(realms_contract, 0, 0, address);
    // mint realms
    IRealms.mint(realms_contract, account2, Uint256(TARGET_REALM_ID, 0));
    // set data
    IRealms.set_realm_data(
        realms_contract, Uint256(TARGET_REALM_ID, 0), 0, 40564819207303341694527483217926
    );

    // directly change in the storage the amounts
    %{
        store(context.resources_contract, "ERC1155_balances", [100*ids.BOUNTY_AMOUNT], [1, 0, context.self_address])
        store(context.resources_contract, "ERC1155_balances", [100*ids.BOUNTY_AMOUNT], [2, 0, context.self_address])
        store(context.resources_contract, "ERC1155_balances", [100*ids.BOUNTY_AMOUNT], [3, 0, context.self_address])

        store(context.resources_contract, "ERC1155_balances", [ids.BOUNTY_AMOUNT], [1, 0, context.combat_contract])
        store(context.resources_contract, "ERC1155_balances", [ids.BOUNTY_AMOUNT], [2, 0, context.combat_contract])
        store(context.resources_contract, "ERC1155_balances", [ids.BOUNTY_AMOUNT], [3, 0, context.combat_contract])
    %}

    return ();
}

// check the difference in resources balance between before and after combat
@external
func test_claim_without_bounties_should_revert{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() -> () {
    // claim bounty
    %{
        stop_prank_callable = start_prank(context.account1, context.self_address)
        expect_revert(error_message="No bounties on this realm")
    %}
    claim_bounties(
        target_realm_id=Uint256(TARGET_REALM_ID, 0),
        attacking_realm_id=Uint256(ATTACKING_REALM_ID, 0),
        attacking_army_id=ATTACKING_ARMY_ID,
        defending_army_id=DEFENDING_ARMY_ID,
    );

    return ();
}

@external
func test_claim_with_bounties{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() -> () {
    // setup bounties in mercenary contract
    alloc_locals;
    local self_address;
    %{
        ids.self_address = context.self_address
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            if (i <= 9):
                # 10 times
                # lords bounties
                store(context.self_address, "bounties", [1, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 500, 1, 0)], [ids.TARGET_REALM_ID, 0, i])
            if (i >= 10 and i < 40):
                # 30 resource bounties
                store(context.self_address, "bounties", [1, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 1000, 0, 1)], [ids.TARGET_REALM_ID, 0, i])
            if (i>=40):
                # 10 times
                # resource bounties
                store(context.self_address, "bounties", [1, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 1000, 0, 2)], [ids.TARGET_REALM_ID, 0, i])

        # verify that the bounty is correct
        bounty = load(context.self_address, "bounties", "PackedBounty", [ids.TARGET_REALM_ID, 0, 12])
        assert bounty == [1, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 1000, 0, 1)]
    %}

    %{ stop_prank_callable = start_prank(context.account1, context.self_address) %}
    claim_bounties(
        target_realm_id=Uint256(TARGET_REALM_ID, 0),
        attacking_realm_id=Uint256(ATTACKING_REALM_ID, 0),
        attacking_army_id=ATTACKING_ARMY_ID,
        defending_army_id=DEFENDING_ARMY_ID,
    );
    %{ stop_prank_callable() %}

    // verify bounty resets
    %{
        # verify that the bounty is removed after claim
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):        
            bounty = load(context.self_address, "bounties", "PackedBounty", [ids.TARGET_REALM_ID, 0, i])
            assert bounty == [0, 0], f'bounty is {bounty}'
    %}

    // verify value transfers
    %{
        ## verify that account1 received amounts for lords
        attacker_lords_amount_contract = load(context.lords_contract, "ERC20_balances", "felt", [context.account1])[0]
        ## verify that this contract stored the right dev fees
        dev_lords_amount_contract = load(context.self_address, "dev_fees_lords", "Uint256")[0]
        # equal amount from bounties 
        total_lords_amount =  10*ids.BOUNTY_AMOUNT
        # amount going to fees
        dev_lords_amount = divmod(total_lords_amount, 10)[0]
        attacker_lords_amount = total_lords_amount - dev_lords_amount
        assert attacker_lords_amount_contract == attacker_lords_amount, f'should be {attacker_lords_amount} but is {attacker_lords_amount_contract}'
        assert dev_lords_amount_contract == dev_lords_amount, f'should be {dev_lords_amount} but is {dev_lords_amount_contract}'

        ## verify that account1 received amounts for token id 1,0
        attacker_resources1_amount_contract = load(context.resources_contract, "ERC1155_balances", "felt", [1, 0, context.account1])[0]
        ## verify that this contract stored the right dev fees
        dev_resources1_amount_contract = load(context.self_address, "dev_fees_resources", "Uint256", [1, 0])[0]
        # equal amount from bounties 
        resources1_amount =  ids.BOUNTY_AMOUNT
        ## amount going to fees
        # per bounty
        dev_resources1_amount = divmod(resources1_amount, 10)[0]
        # total (30 bounties)
        dev_total_resources1_amount = 30*dev_resources1_amount

        ## amount going to attacker
        # per bounty
        attacker_resources1_amount = resources1_amount - dev_resources1_amount
        # total (30 bounties)
        attacker_total_resources1_amount = 30*attacker_resources1_amount
        # what was gained from winning combat (received token 2,0 and token 3,0 from combat module)
        assert attacker_resources1_amount_contract == attacker_total_resources1_amount, f'should be {attacker_total_resources1_amount} but is {attacker_resources1_amount_contract}'
        assert dev_resources1_amount_contract == dev_total_resources1_amount, f'should be {dev_total_resources1_amount} but is {dev_resources1_amount_contract}'

        ## verify that account1 received amounts for token id 2,0
        attacker_resources2_amount_contract = load(context.resources_contract, "ERC1155_balances", "felt", [2, 0, context.account1])[0]
        ## verify that this contract stored the right dev fees
        dev_resources2_amount_contract = load(context.self_address, "dev_fees_resources", "Uint256", [2, 0])[0]
        # equal amount from bounties 
        resources2_amount =  ids.BOUNTY_AMOUNT
        ## amount going to fees
        # per bounty
        dev_resources2_amount = divmod(resources2_amount, 10)[0]
        # total (10 bounties)
        dev_total_resources2_amount = 10*dev_resources2_amount

        ## amount going to attacker
        # per bounty
        attacker_resources2_amount = resources2_amount - dev_resources2_amount
        # total (10 bounties)
        attacker_total_resources2_amount = 10*attacker_resources2_amount
        # what was gained from winning combat (received token 2,0 and token 3,0 from combat module)
        attacker_total_resources2_amount += 1*10**18
        assert attacker_resources2_amount_contract == attacker_total_resources2_amount, f'should be {attacker_total_resources2_amount} but is {attacker_resources2_amount_contract}'
        assert dev_resources2_amount_contract == dev_total_resources2_amount, f'should be {dev_total_resources2_amount} but is {dev_resources2_amount_contract}'
    %}

    // verify the emitted events for claimed bounty
    %{
        # lords fees events = 10% of total lords amount
        (increase_total_lords_fees, _) = divmod(ids.BOUNTY_AMOUNT*10, 10)
        # resource fees events = 10% of each resource amount
        (increase_resource_fees, _) = divmod(ids.BOUNTY_AMOUNT, 10)
        expect_events(
        {"name": "BountiesClaimed", 
         "data": {
            "target_realm_id": ids.TARGET_REALM_ID, 
            "attacker_lords_amount": {"low": attacker_lords_amount, "high": 0}, 
            "dev_lords_amount": {"low": dev_lords_amount, "high": 0}, 
            "resources_ids": 30*[{"low": 1, "high": 0}] + 10*[{"low": 2, "high": 0}], 
            "attacker_resources_amounts": 30*[{"low": attacker_resources1_amount, "high": 0}] + 10*[{"low": attacker_resources2_amount, "high": 0}], 
            "dev_resources_amounts": 30*[{"low": dev_resources1_amount, "high": 0}] + 10*[{"low": dev_resources2_amount, "high": 0}], 
        }}
        ),
    %}

    return ();
}

@external
func test_claim_with_expired_bounties_should_revert{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() -> () {
    // setup bounties in mercenary contract
    alloc_locals;
    local self_address;
    %{
        ids.self_address = context.self_address
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            if (i <= 9):
                # 10 times
                # lords bounties
                store(context.self_address, "bounties", [context.account2, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 500, 1, 0)], [ids.TARGET_REALM_ID, 0, i])
            if (i >= 10 and i < 40):
                # 30 resource bounties
                store(context.self_address, "bounties", [context.account2, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 1000, 0, 1)], [ids.TARGET_REALM_ID, 0, i])
            if (i>=40):
                # 10 times
                # resource bounties
                store(context.self_address, "bounties", [context.account2, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 1000, 0, 2)], [ids.TARGET_REALM_ID, 0, i])

        # verify that the bounty is correct
        bounty = load(context.self_address, "bounties", "PackedBounty", [ids.TARGET_REALM_ID, 0, 12])
        assert bounty == [context.account2, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 1000, 0, 1)]
    %}

    // go into the future to make all bounties expired
    %{
        stop_roll = roll(1000)
        stop_prank_callable = start_prank(context.account1, context.self_address)
        expect_revert(error_message="No bounties on this realm")
    %}

    claim_bounties(
        target_realm_id=Uint256(TARGET_REALM_ID, 0),
        attacking_realm_id=Uint256(ATTACKING_REALM_ID, 0),
        attacking_army_id=ATTACKING_ARMY_ID,
        defending_army_id=DEFENDING_ARMY_ID,
    );
    %{ stop_prank_callable() %}

    return ();
}
