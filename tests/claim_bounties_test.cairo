%lang starknet

from starkware.cairo.common.uint256 import Uint256, uint256_sub
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)
from starkware.cairo.common.alloc import alloc

from contracts.library import MercenaryLib

from contracts.mercenary import issue_bounty, onERC1155BatchReceived, claim_bounties
from contracts.storage import supportsInterface
from contracts.structures import Bounty, BountyType

from realms_contracts_git.contracts.settling_game.utils.game_structs import RealmData

@contract_interface
namespace IRealms {
    func initializer(name: felt, symbol: felt, proxy_admin: felt) {
    }
    func approve(approved: felt, tokenId: Uint256) {
    }
    func mint(to: felt, tokenId: Uint256) {
    }
    func set_realm_data(tokenId: Uint256, _realm_name: felt, _realm_data: felt) {
    }
    func fetch_realm_data(realm_id: Uint256) -> (realm_stats: RealmData) {
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

@contract_interface
namespace IERC20 {
    func mint(to: felt, tokenId: Uint256) {
    }
    func ownerOf(tokenId: Uint256) -> (owner: felt) {
    }
    func approve(spender: felt, amount: Uint256) -> (success: felt) {
    }
    func transfer(recipient: felt, amount: Uint256) -> (success: felt) {
    }
}

@contract_interface
namespace IERC1155 {
    func initializer(uri: felt, proxy_admin: felt) {
    }
    func mint(to: felt, id: Uint256, amount: Uint256, data_len: felt, data: felt*) -> () {
    }
    func mintBatch(
        to: felt,
        ids_len: felt,
        ids: Uint256*,
        amounts_len: felt,
        amounts: Uint256*,
        data_len: felt,
        data: felt*,
    ) -> () {
    }
    func setApprovalForAll(operator: felt, approved: felt) {
    }
    func safeBatchTransferFrom(
        _from: felt,
        to: felt,
        ids_len: felt,
        ids: Uint256*,
        amounts_len: felt,
        amounts: Uint256*,
        data_len: felt,
        data: felt*,
    ) {
    }
    func balanceOf(account: felt, id: Uint256) -> (balance: Uint256) {
    }
}

@contract_interface
namespace IArgentAccount {
    func initialize(signer: felt, guardian: felt) {
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

        ## deploy module controller to use the staked realm mint
        ids.mc_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/ModuleController.cairo").contract_address
        context.mc_contract = ids.mc_contract


        ## set local storage vars
        store(context.self_address, "lords_contract", [context.lords_contract])
        store(context.self_address, "erc1155_contract", [context.resources_contract])
        store(context.self_address, "realm_contract", [context.realms_contract])
        store(context.self_address, "staked_realm_contract", [context.s_realms_contract])
        store(context.self_address, "combat_module", [context.combat_contract])
        store(context.self_address, "bounty_count_limit", [ids.BOUNTY_COUNT_LIMIT])
        store(context.self_address, "fees_percentage", [0])

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
    // mint realm for account 2 (defeding) and set data
    IRealms.initializer(realms_contract, 0, 0, address);
    // mint realms
    IRealms.mint(realms_contract, account2, Uint256(TARGET_REALM_ID, 0));
    // set data
    IRealms.set_realm_data(
        realms_contract, Uint256(TARGET_REALM_ID, 0), 0, 40564819207303341694527483217926
    );

    // erc1155 initializer
    IERC1155.initializer(resources_contract, 0, address);

    // mint and transfer resources to mercenary contract
    let (resources_ids: Uint256*) = alloc();
    assert resources_ids[0] = Uint256(1, 0);
    assert resources_ids[1] = Uint256(2, 0);
    assert resources_ids[2] = Uint256(3, 0);

    let (resources_amounts: Uint256*) = alloc();
    assert resources_amounts[0] = Uint256(100 * BOUNTY_AMOUNT, 0);
    assert resources_amounts[1] = Uint256(100 * BOUNTY_AMOUNT, 0);
    assert resources_amounts[2] = Uint256(100 * BOUNTY_AMOUNT, 0);

    let (data: felt*) = alloc();
    assert data[0] = 0;

    // TODO: also directly change the storage for this contract, don't use mintbatch
    IERC1155.mintBatch(
        contract_address=resources_contract,
        to=address,
        ids_len=3,
        ids=resources_ids,
        amounts_len=3,
        amounts=resources_amounts,
        data_len=1,
        data=data,
    );

    // directly change in the storage the amounts
    %{
        store(context.resources_contract, "ERC1155_balances", [ids.BOUNTY_AMOUNT], [1, 0, context.combat_contract])
        store(context.resources_contract, "ERC1155_balances", [ids.BOUNTY_AMOUNT], [2, 0, context.combat_contract])
        store(context.resources_contract, "ERC1155_balances", [ids.BOUNTY_AMOUNT], [3, 0, context.combat_contract])
    %}

    return ();
}

// check the difference in resources balance between before and after combat
// TODO: add realms data to the nft
@external
func test_claim_without_bounties{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> () {
    // claim bounty
    %{ stop_prank_callable = start_prank(context.account1, context.self_address) %}
    claim_bounties(
        target_realm_id=TARGET_REALM_ID,
        attacking_realm_id=ATTACKING_REALM_ID,
        attacking_army_id=ATTACKING_ARMY_ID,
        defending_army_id=DEFENDING_ARMY_ID,
    );
    %{ stop_prank_callable() %}

    %{
        resources_amount = load(context.resources_contract, "ERC1155_balances", "felt", [2, 0, context.account1])
        assert resources_amount[0] == 1*10**18, f'the resource balance should be equal to {1*10**18} but is {resources_amount[0]}'

        resources_amount = load(context.resources_contract, "ERC1155_balances", "felt", [3, 0, context.account1])
        assert resources_amount[0] == 1*10**18, f'the resource balance should be equal to {1*10**18} but is {resources_amount[0]}'
    %}

    return ();
}

@external
func test_claim_with_bounties{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> () {
    // setup bounties in mercenary contract
    alloc_locals;
    local self_address;
    %{
        ids.self_address = context.self_address
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            if (i <= 9):
                # 10 times
                # lords bounties
                store(context.self_address, "bounties", [0, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0], [ids.TARGET_REALM_ID, i])
            if (i >= 10 and i < 40):
                # 30 resource bounties
                store(context.self_address, "bounties", [0, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0], [ids.TARGET_REALM_ID, i])
            if (i>=40):
                # 10 times
                # resource bounties
                store(context.self_address, "bounties", [0, ids.BOUNTY_AMOUNT, 0, 1000, 0, 2, 0], [ids.TARGET_REALM_ID, i])

        # verify that the bounty is correct
        bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 12])
        assert bounty == [0, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0]
    %}

    %{ stop_prank_callable = start_prank(context.account1, context.self_address) %}
    claim_bounties(
        target_realm_id=TARGET_REALM_ID,
        attacking_realm_id=ATTACKING_REALM_ID,
        attacking_army_id=ATTACKING_ARMY_ID,
        defending_army_id=DEFENDING_ARMY_ID,
    );
    %{ stop_prank_callable() %}

    %{
        # verify that the bounty is removed after claim
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):        
            bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, i])
            assert bounty == [0, 0, 0, 0, 0, 0, 0]

        # verify that the account1 received the new tokens
        resources_amount = load(context.resources_contract, "ERC1155_balances", "felt", [1, 0, context.account1]) 
        amount = 30*ids.BOUNTY_AMOUNT
        assert resources_amount[0] == amount, f'resources amount for token id 1 should be {amount} but is {resources_amount}'

        resources_amount = load(context.resources_contract, "ERC1155_balances", "felt", [2, 0, context.account1]) 
        # equal amount from bounties + what was gained from winning combat
        amount =  10*ids.BOUNTY_AMOUNT + 1*10**18
        assert resources_amount[0] == amount, f'resources amount for token id 2 should be {amount} but is {resources_amount}'
    %}

    return ();
}
