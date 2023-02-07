%lang starknet

// starkware
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_contract_address, get_block_timestamp
from starkware.cairo.common.alloc import alloc

// mercenary
from contracts.mercenary import issue_bounty, onERC1155Received
from contracts.storage import supportsInterface
from contracts.structures import Bounty, BountyType, PackedBounty

// realms
from realms_contracts_git.contracts.settling_game.utils.game_structs import ExternalContractIds

@contract_interface
namespace IRealms {
    func initializer(name: felt, symbol: felt, proxy_admin: felt) {
    }
    func set_realm_data(tokenId: Uint256, _realm_name: felt, _realm_data: felt) {
    }
}

@contract_interface
namespace IERC20 {
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
    local mc_contract;

    %{
        # import the unpack, pack functions
        import sys
        sys.path.insert(0,'tests')
        from utils import pack_bounty_info, unpack_bounty_info
        context.pack_bounty_info = pack_bounty_info
        context.unpack_bounty_info = unpack_bounty_info
    %}

    %{
        ## deploy lords and resources contract
        context.self_address = ids.address
        context.lords_contract = deploy_contract("lib/cairo_contracts_git/src/openzeppelin/token/erc20/presets/ERC20Mintable.cairo",
         [0, 0, 6, ids.MINT_AMOUNT, 0, ids.address, ids.address]).contract_address
        ids.lords_contract = context.lords_contract
        context.resources_contract = deploy_contract("lib/realms_contracts_git/contracts/token/ERC1155_Mintable_Burnable.cairo").contract_address
        ids.resources_contract = context.resources_contract

        ## deploy user accounts
        context.account1 = deploy_contract('./lib/argent_contracts_starknet_git/contracts/account/ArgentAccount.cairo').contract_address
        ids.account1 = context.account1

        ## deploy realms nft contract
        ids.realms_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/tokens/Realms_ERC721_Mintable.cairo").contract_address
        context.realms_contract = ids.realms_contract

        ## deploy modules controller contract and setup external contract and modules ids
        context.mc_contract = deploy_contract("./lib/realms_contracts_git/contracts/settling_game/ModuleController.cairo").contract_address
        ids.mc_contract = context.mc_contract
        # store in module controller
        store(context.mc_contract, "external_contract_table", [context.resources_contract], [ids.ExternalContractIds.Resources])
        store(context.mc_contract, "external_contract_table", [context.lords_contract], [ids.ExternalContractIds.Lords])
        store(context.mc_contract, "external_contract_table", [context.realms_contract], [ids.ExternalContractIds.Realms])

        # store in local contract
        store(context.self_address, "module_controller_address", [context.mc_contract])

        ## set local storage vars
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

    IERC1155.initializer(resources_contract, 0, address);
    // mint and transfer resources to user 1
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
func test_issue_lords_bounty{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() {
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

    // create bounty with lords
    let bounty_type = BountyType(is_lords=1, resource_id=Uint256(0, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 1000;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    // give allowance of amount from this user to this contract
    %{
        stop_prank_callable = start_prank(ids.account1, target_contract_address=context.lords_contract)
        ## verify allowance from event
        expect_events({"name": "Approval", "data": [ids.account1, context.self_address, ids.BOUNTY_AMOUNT, 0], "from_address": context.lords_contract})
    %}
    let (success) = IERC20.approve(
        contract_address=lords_contract, spender=self_address, amount=Uint256(BOUNTY_AMOUNT, 0)
    );
    %{
        ## verify allowance from contract storage
        allowance = load(context.lords_contract, "ERC20_allowances", "Uint256", [ids.account1, context.self_address])
        assert allowance == [ids.BOUNTY_AMOUNT, 0], f'allowance not equal to ${allowance} in the contract but should be ${[ids.BOUNTY_AMOUNT, 0]}'
    %}
    %{ stop_prank_callable() %}

    // account1 issues a new bounty
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}
    let (index) = issue_bounty(target_realm_id=Uint256(TARGET_REALM_ID, 0), bounty=bounty);

    // verify the bounty values in the storage
    %{
        issued_bounty_packed = load(context.self_address, "bounties", "PackedBounty", [ids.TARGET_REALM_ID, 0, ids.index])                      
        resource_id, is_lords, deadline, amount = context.unpack_bounty_info(issued_bounty_packed[1])
        assert issued_bounty_packed[0] == ids.account1, f'owner of the bounty {issued_bounty_packed[0]} not equal to {ids.account1}'   # owner
        assert amount == ids.BOUNTY_AMOUNT, f'amount of the bounty {amount} not equal to {ids.BOUNTY_AMOUNT}'                          # amount.low 
        assert deadline == ids.deadline, f'deadline of the bounty {deadline} not equal to {ids.deadline}'                              # deadline   
        assert is_lords == 1, f'is_lords {is_lords} not equal to {1}'                                                                  # is_lords     
        assert resource_id == 0, f'resource_id {resource_id} not equal to {0}'                                                         # resource low
    %}

    return ();
}

@external
func test_issue_resources_bounty{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() {
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

    // create bounty with resources
    let bounty_type = BountyType(is_lords=0, resource_id=Uint256(1, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 1000;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    // give allowance of amount from this user to this contract
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.resources_contract) %}
    IERC1155.setApprovalForAll(
        contract_address=resources_contract, operator=self_address, approved=1
    );
    %{ stop_prank_callable() %}

    // issue new bounty
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}
    let (index) = issue_bounty(target_realm_id=Uint256(TARGET_REALM_ID, 0), bounty=bounty);

    // verify the bounty values in the storage
    %{
        issued_bounty_packed = load(context.self_address, "bounties", "PackedBounty", [ids.TARGET_REALM_ID, 0, ids.index])                      
        resource_id, is_lords, deadline, amount = context.unpack_bounty_info(issued_bounty_packed[1])
        assert issued_bounty_packed[0] == ids.account1, f'owner of the bounty {issued_bounty_packed[0]} not equal to {ids.account1}'   # owner
        assert amount == ids.BOUNTY_AMOUNT, f'amount of the bounty {amount} not equal to {ids.BOUNTY_AMOUNT}'                          # amount.low 
        assert deadline == ids.deadline, f'deadline of the bounty {deadline} not equal to {ids.deadline}'                              # deadline   
        assert is_lords == 0, f'is_lords {is_lords} not equal to {0}'                                                                  # is_lords     
        assert resource_id == 1, f'resource_id {resource_id} not equal to {0}'                                                         # resource low
    %}

    return ();
}

@external
func test_max_bounties_should_revert{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() {
    alloc_locals;
    local lords_contract;
    local self_address;
    local account1;
    %{
        ids.self_address = context.self_address
        ids.lords_contract = context.lords_contract
        ids.account1 = context.account1
    %}

    // create lords bounty
    let bounty_type = BountyType(is_lords=1, resource_id=Uint256(0, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 1000;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    // fill all the bounties slot for one realm
    %{
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            store(context.self_address, "bounties", [ids.account1, context.pack_bounty_info(ids.BOUNTY_AMOUNT, ids.deadline, 1, 0)], [ids.TARGET_REALM_ID, 0, i])
    %}

    // give allowance of amount from this user to this contract
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.lords_contract) %}
    let (success) = IERC20.approve(
        contract_address=lords_contract, spender=self_address, amount=Uint256(BOUNTY_AMOUNT, 0)
    );
    %{ stop_prank_callable() %}

    // expect the tx to revert when no more slots
    %{ expect_revert(error_message="Maximum number of bounties reached") %}
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}
    let (index) = issue_bounty(target_realm_id=Uint256(TARGET_REALM_ID, 0), bounty=bounty);

    return ();
}

@external
func test_replace_expired_bounty{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() {
    alloc_locals;
    local lords_contract;
    local self_address;
    local account1;
    %{
        ids.self_address = context.self_address
        ids.lords_contract = context.lords_contract
        ids.account1 = context.account1
    %}

    // create new lords bounty
    let bounty_type = BountyType(is_lords=1, resource_id=Uint256(0, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 1500;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    // fill all the bounties slot for one realm
    %{
        for i in range(0, ids.BOUNTY_COUNT_LIMIT):
            if i == 21:
                store(context.self_address, "bounties", [ids.account1, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 500, 1, 0)], [ids.TARGET_REALM_ID, 0, i])
            else:
                store(context.self_address, "bounties", [ids.account1, context.pack_bounty_info(ids.BOUNTY_AMOUNT, 1000, 1, 0)], [ids.TARGET_REALM_ID, 0, i])
    %}

    // jump forward in time so that some bounties are no more valid
    %{ stop_roll = roll(500) %}

    // give allowance of amount from this user to this contract
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.lords_contract) %}
    let (success) = IERC20.approve(
        contract_address=lords_contract, spender=self_address, amount=Uint256(BOUNTY_AMOUNT, 0)
    );
    %{ stop_prank_callable() %}

    // issue new bounty and check that the bounty took the slot of an expired bounty
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}
    let (index) = issue_bounty(target_realm_id=Uint256(TARGET_REALM_ID, 0), bounty=bounty);
    %{ stop_prank_callable() %}
    %{
        ## assert that the expired bounty at index 21 was replaced
        assert ids.index == 21, f'The index {ids.index} is not equal to 21'
        issued_bounty_packed = load(context.self_address, "bounties", "PackedBounty", [ids.TARGET_REALM_ID, 0, 21])                      
        resource_id, is_lords, deadline, amount = context.unpack_bounty_info(issued_bounty_packed[1])
        assert deadline == ids.deadline, f'deadline of the bounty {deadline} not equal to {ids.deadline}'                  # deadline

        ## assert that the bounty owner received back his money
        lords_balance = load(ids.lords_contract, "ERC20_balances", "Uint256", [ids.account1])[0]
        assert lords_balance == ids.BOUNTY_AMOUNT, f'amount of lords in account1 should be {ids.BOUNTY_AMOUNT} but is {lords_balance}'
    %}

    return ();
}

@external
func test_not_big_enough_delay_should_revert{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() {
    alloc_locals;
    local lords_contract;
    local self_address;
    local account1;
    %{
        ids.self_address = context.self_address
        ids.lords_contract = context.lords_contract
        ids.account1 = context.account1
    %}

    // create lords bounty
    let bounty_type = BountyType(is_lords=1, resource_id=Uint256(0, 0));
    let (ts) = get_block_timestamp();
    local deadline = ts + 50;
    let bounty = Bounty(
        owner=account1, amount=Uint256(BOUNTY_AMOUNT, 0), deadline=deadline, type=bounty_type
    );

    // give allowance of amount from this user to this contract
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.lords_contract) %}
    let (success) = IERC20.approve(
        contract_address=lords_contract, spender=self_address, amount=Uint256(BOUNTY_AMOUNT, 0)
    );
    %{ stop_prank_callable() %}

    // should fail because the deadline is not far away enough in the future (50 < 100)
    %{ expect_revert(error_message="Deadline not far enough in time") %}
    %{ stop_prank_callable = start_prank(ids.account1, target_contract_address=context.self_address) %}
    let (index) = issue_bounty(target_realm_id=Uint256(TARGET_REALM_ID, 0), bounty=bounty);

    return ();
}
