%lang starknet

from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)
from starkware.cairo.common.alloc import alloc

from contracts.mercenary import issue_bounty, onERC1155Received
from contracts.storage import supportsInterface
from contracts.structures import Bounty, BountyType

@contract_interface
namespace IRealms {
    func initializer(name: felt, symbol: felt, proxy_admin: felt) {
    }
    func set_realm_data(tokenId: Uint256, _realm_name: felt, _realm_data: felt) {
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
    func setApprovalForAll(operator: felt, approved: felt) {
    }
}

const MINT_AMOUNT = 100 * 10 ** 18;
const REALM_CONTRACT = 121;
const S_REALM_CONTRACT = 122;
const COMBAT_MODULE = 123;
const BOUNTY_AMOUNT = 5 * 10 ** 18;
const TARGET_REALM_ID = 125;
const BOUNTY_COUNT_LIMIT = 50;
const BOUNTY_DEADLINE_LIMIT = 100;

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    let (address) = get_contract_address();
    local resources_contract;
    local lords_contract;
    local account1;
    local realms_contract;
    %{
        context.self_address = ids.address
        context.lords_contract = deploy_contract("lib/cairo_contracts_git/src/openzeppelin/token/erc20/presets/ERC20Mintable.cairo", [0, 0, 6, ids.MINT_AMOUNT, 0, ids.address, ids.address]).contract_address
        context.resources_contract = deploy_contract("lib/realms_contracts_git/contracts/token/ERC1155_Mintable_Burnable.cairo").contract_address

        ## deploy user accounts
        context.account1 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account1 = context.account1

        ## deploy realms nft contract
        ids.realms_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/tokens/Realms_ERC721_Mintable.cairo").contract_address
        context.realms_contract = ids.realms_contract

        ids.resources_contract = context.resources_contract
        ids.lords_contract = context.lords_contract
        store(context.self_address, "lords_contract", [context.lords_contract])
        store(context.self_address, "realm_contract", [context.realms_contract])
        store(context.self_address, "erc1155_contract", [context.resources_contract])
        store(context.self_address, "bounty_count_limit", [ids.BOUNTY_COUNT_LIMIT])
        store(context.self_address, "bounty_deadline_limit", [ids.BOUNTY_DEADLINE_LIMIT])
    %}

    // initialize realms contract
    IRealms.initializer(contract_address=realms_contract, name=0, symbol=0, proxy_admin=address);

    // set realm data
    IRealms.set_realm_data(
        contract_address=realms_contract,
        tokenId=Uint256(TARGET_REALM_ID, 0),
        _realm_name='test1',
        _realm_data=40564819207303341694527483217926,
    );

    // transfer amount to user 1 and 2
    IERC20.transfer(
        contract_address=lords_contract, recipient=account1, amount=Uint256(BOUNTY_AMOUNT, 0)
    );

    // TODO do the real initializer
    IERC1155.initializer(resources_contract, 0, address);
    // mint and transfer resources to user 1 and 2
    let (local data: felt*) = alloc();
    assert data[0] = 0;
    IERC1155.mint(
        contract_address=resources_contract,
        to=account1,
        id=Uint256(1, 0),
        amount=Uint256(BOUNTY_AMOUNT, 0),
        data_len=1,
        data=data,
    );
    return ();
}

@external
func test_deploy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    %{
        import numpy as np
        lords_limit_amount = [10, 0]
        resources_amount = [10, 0]
        resource_len = token_ids_len = 4
        token_ids = [0, 0, 1, 0, 2, 0, 3, 0]
        resources_amount_array = resource_len*resources_amount 
        context.mercenary_address = deploy_contract("./contracts/mercenary.cairo", 
                       [context.self_address, 
                        ids.REALM_CONTRACT, 
                        ids.S_REALM_CONTRACT, 
                        context.resources_contract, 
                        context.lords_contract, 
                        ids.COMBAT_MODULE, 
                        0, 
                        ids.BOUNTY_COUNT_LIMIT,
                        *lords_limit_amount, 
                        resource_len, 
                        *resources_amount_array,
                        token_ids_len,
                        *token_ids,
                        ids.BOUNTY_DEADLINE_LIMIT]).contract_address
        owner = load(context.mercenary_address, "Ownable_owner", "felt")[0]
        realms_contract = load(context.mercenary_address, "realm_contract", "felt")[0]
        resources_contract = load(context.mercenary_address, "erc1155_contract", "felt")[0]
        combat_module = load(context.mercenary_address, "combat_module", "felt")[0]
        lords_contract = load(context.mercenary_address, "lords_contract", "felt")[0]

        ## check that the bounty_amount_limit_resources storage was correctly filled
        for i in range(0, 4):
            if (i%2 == 0):
                resource_amount = load(context.mercenary_address, "bounty_amount_limit_resources", "Uint256", [token_ids[i], token_ids[i+1]])
                resource_amount_true = [resources_amount_array[i], resources_amount_array[i+1]] 
                assert resource_amount == resource_amount_true, f'resource amount in contract is {resource_amount} while should be {resource_amount_true}'

        assert owner == context.self_address, f'owner error, expected {context.self_address}, got {owner}'
        assert realms_contract == ids.REALM_CONTRACT, f'realms_contract error, expected {ids.REALM_CONTRACT}, got {realms_contract}'
        assert resources_contract == context.resources_contract, f'resource_contract error, expected {context.resources_contract}, got {resources_contract}'
        assert combat_module == ids.COMBAT_MODULE, f'combat_module error, expected {ids.COMBAT_MODULE}, got {combat_module}'
        assert lords_contract == context.lords_contract, f'lords_contract error, expected {context.lords_contract}, got {lords_contract}'
    %}
    return ();
}

@external
func test_issue_lords_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    // store bounty_count_limit
    alloc_locals;
    local lords_contract;
    local self_address;
    local account1;
    %{
        ids.self_address = context.self_address
        ids.lords_contract = context.lords_contract
        ids.account1 = context.account1
    %}

    // CREATE BOUNTY
    let bounty_type = BountyType(is_lords=1, resource=Uint256(0, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 1000;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.lords_contract) %}
    // give allowance of amount from this user to this contract
    let (success) = IERC20.approve(
        contract_address=lords_contract, spender=self_address, amount=Uint256(BOUNTY_AMOUNT, 0)
    );
    %{ expect_events({"name": "Approval", "data": [ids.account1, context.self_address, ids.BOUNTY_AMOUNT, 0], "from_address": context.lords_contract}) %}

    %{
        allowance = load(context.lords_contract, "ERC20_allowances", "Uint256", [ids.account1, context.self_address])
        assert allowance == [ids.BOUNTY_AMOUNT, 0], f'allowance not equal to ${allowance} in the contract but should be ${[ids.BOUNTY_AMOUNT, 0]}'
    %}
    %{ stop_prank_callable() %}

    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}

    let (index) = issue_bounty(target_realm_id=TARGET_REALM_ID, bounty=bounty);

    %{ stop_prank_callable() %}

    %{
        issued_bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, ids.index])                      
        assert issued_bounty[0] == ids.account1, f'owner of the bounty {issued_bounty[0]} not equal to {ids.account1}'                     # owner
        assert issued_bounty[1] == ids.BOUNTY_AMOUNT, f'amount.low of the bounty {issued_bounty[1]} not equal to {ids.BOUNTY_AMOUNT}'      # amount.low 
        assert issued_bounty[2] == 0, f'amount.high of the bounty {issued_bounty[2]} not equal to {0}'                                     # amount.high
        assert issued_bounty[3] == ids.deadline, f'deadline of the bounty {issued_bounty[3]} not equal to {ids.deadline}'                  # deadline   
        assert issued_bounty[4] == 1, f'is_lords {issued_bounty[4]} not equal to {1}'                                                      # is_lords     
        assert issued_bounty[5] == 0, f'resource_id.low {issued_bounty[5]} not equal to {0}'                                               # resource low   
        assert issued_bounty[6] == 0, f'resource_id.high {issued_bounty[6]} not equal to {0}'                                              # resource high
    %}

    return ();
}

@external
func test_issue_resources_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) {
    // store bounty_count_limit
    alloc_locals;
    local resources_contract;
    local self_address;
    local account1;
    %{
        ids.self_address = context.self_address
        ids.resources_contract = context.resources_contract
        ids.account1 = context.account1
    %}

    let bounty_type = BountyType(is_lords=0, resource=Uint256(1, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 1000;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.resources_contract) %}

    // give allowance of amount from this user to this contract
    IERC1155.setApprovalForAll(
        contract_address=resources_contract, operator=self_address, approved=1
    );

    %{ stop_prank_callable() %}

    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}

    let (index) = issue_bounty(target_realm_id=TARGET_REALM_ID, bounty=bounty);

    %{ stop_prank_callable() %}

    %{
        issued_bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, ids.index])                      
        assert issued_bounty[0] == ids.account1, f'owner of the bounty {issued_bounty[0]} not equal to {ids.account1}'                     # owner
        assert issued_bounty[1] == ids.BOUNTY_AMOUNT, f'amount.low of the bounty {issued_bounty[1]} not equal to {ids.BOUNTY_AMOUNT}'      # amount.low 
        assert issued_bounty[2] == 0, f'amount.high of the bounty {issued_bounty[2]} not equal to {0}'                                     # amount.high
        assert issued_bounty[3] == ids.deadline, f'deadline of the bounty {issued_bounty[3]} not equal to {ids.deadline}'                  # deadline   
        assert issued_bounty[4] == 0, f'is_lords {issued_bounty[4]} not equal to {0}'                                                      # is_lords     
        assert issued_bounty[5] == 1, f'resource_id.low {issued_bounty[5]} not equal to {0}'                                               # resource low   
        assert issued_bounty[6] == 0, f'resource_id.high {issued_bounty[6]} not equal to {0}'                                              # resource high
    %}

    return ();
}

@external
func test_max_bounties_should_fail{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) {
    // store bounty_count_limit
    alloc_locals;
    local lords_contract;
    local self_address;
    local account1;
    %{
        ids.self_address = context.self_address
        ids.lords_contract = context.lords_contract
        ids.account1 = context.account1
    %}

    // CREATE BOUNTY
    let bounty_type = BountyType(is_lords=1, resource=Uint256(0, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 1000;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    // fill all the bounties slot for one realm
    %{
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, ids.deadline, 1, 0, 0], [ids.TARGET_REALM_ID, i])
    %}

    // TODO: is it supposed to be a certain message ?
    %{ expect_revert(error_message="maximum number of bounties reached") %}

    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.lords_contract) %}
    // give allowance of amount from this user to this contract
    let (success) = IERC20.approve(
        contract_address=lords_contract, spender=self_address, amount=Uint256(BOUNTY_AMOUNT, 0)
    );
    %{ stop_prank_callable() %}

    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}
    let (index) = issue_bounty(target_realm_id=TARGET_REALM_ID, bounty=bounty);
    %{ stop_prank_callable() %}

    return ();
}

@external
func test_replace_expired_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) {
    alloc_locals;
    local lords_contract;
    local self_address;
    local account1;
    %{
        ids.self_address = context.self_address
        ids.lords_contract = context.lords_contract
        ids.account1 = context.account1
    %}

    // CREATE BOUNTY
    let bounty_type = BountyType(is_lords=1, resource=Uint256(0, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 1500;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    // fill all the bounties slot for one realm
    %{
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            if i == 21:
                store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0], [ids.TARGET_REALM_ID, i])
            else:
                store(context.self_address, "bounties", [ids.account1, ids.BOUNTY_AMOUNT, 0, 1000, 1, 0, 0], [ids.TARGET_REALM_ID, i])
    %}

    %{ stop_warp = roll(501) %}

    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.lords_contract) %}
    // give allowance of amount from this user to this contract
    let (success) = IERC20.approve(
        contract_address=lords_contract, spender=self_address, amount=Uint256(BOUNTY_AMOUNT, 0)
    );
    %{ stop_prank_callable() %}

    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}
    let (index) = issue_bounty(target_realm_id=TARGET_REALM_ID, bounty=bounty);
    %{ stop_prank_callable() %}
    %{
        ## assert that the expired bounty at index 21 was replaced
        assert ids.index == 21, f'The index {ids.index} is not equal to 21'
        issued_bounty = load(context.self_address, "bounties", "Bounty", [ids.TARGET_REALM_ID, 21])
        assert issued_bounty[3] == ids.deadline, f'deadline of the bounty {issued_bounty[3]} not equal to {ids.deadline}'                  # deadline

        ## assert that the bounty owner received back his money
        lords_balance = load(ids.lords_contract, "ERC20_balances", "Uint256", [ids.account1])[0] 
        assert lords_balance == ids.BOUNTY_AMOUNT, f'amount of lords in account1 should be {ids.BOUNTY_AMOUNT} but is {lords_balance}'
    %}

    return ();
}

@external
func test_negative_should_fail{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    local lords_contract;
    local self_address;
    local account1;
    %{
        ids.self_address = context.self_address
        ids.lords_contract = context.lords_contract
        ids.account1 = context.account1
    %}

    // CREATE BOUNTY
    let bounty_type = BountyType(is_lords=1, resource=Uint256(0, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 50;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    // should fail because the deadline is not far away enough in the future (50 < 100)
    %{ expect_revert(error_message="deadline not far enough in time") %}
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.lords_contract) %}
    // give allowance of amount from this user to this contract
    let (success) = IERC20.approve(
        contract_address=lords_contract, spender=self_address, amount=Uint256(BOUNTY_AMOUNT, 0)
    );
    %{ stop_prank_callable() %}

    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}
    let (index) = issue_bounty(target_realm_id=TARGET_REALM_ID, bounty=bounty);
    %{ stop_prank_callable() %}

    return ();
}
