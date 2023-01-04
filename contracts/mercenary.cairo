%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
)
from starkware.cairo.common.uint256 import Uint256, uint256_le, assert_uint256_le
from starkware.cairo.common.alloc import alloc

// Mercenary
from contracts.structures import Bounty, BountyType
from contracts.storage import (
    realm_contract,
    stacked_realm_contract,
    erc1155_contract,
    lords_contract,
    combat_module,
    developer_fees,
    bounty_count_limit,
    bounty_amount_limit_lords,
    bounty_amount_limit_resources,
    bounty_deadline_limit,
    bounties,
    bounty_count,
    supportsInterface,
)

// Openzeppelin
from cairo_contracts_git.src.openzeppelin.access.ownable.library import Ownable
from cairo_contracts_git.src.openzeppelin.token.erc721.IERC721 import IERC721
from cairo_contracts_git.src.openzeppelin.token.erc20.IERC20 import IERC20
// Realms
from realms_contracts_git.contracts.settling_game.utils.constants import CCombat
from realms_contracts_git.contracts.settling_game.interfaces.IERC1155 import IERC1155

// -----------------------------------
// Mercenary Logic
// -----------------------------------

const DEVELOPER_FEES_PRECISION = 10 ** 4;
const ON_ERC1155_RECEIVED_SELECTOR = 0xf23a6e61;

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt,
    realm_contract_: felt,
    stacked_realm_contract_: felt,
    erc1155_contract_: felt,
    lords_contract_: felt,
    combat_module_: felt,
    developer_fees_: felt,
    bounty_count_limit: felt,
    bounty_amount_limit_lords_: Uint256,
    amount_limit_resources_len: felt,
    amount_limit_resources: Uint256*,
    token_ids_resources_len: felt,
    token_ids_resources: Uint256*,
    bounty_deadline_limit_: felt,
) {
    Ownable.initializer(owner);
    realm_contract.write(realm_contract_);
    stacked_realm_contract.write(stacked_realm_contract_);
    erc1155_contract.write(erc1155_contract_);
    lords_contract.write(lords_contract_);
    combat_module.write(combat_module_);
    developer_fees.write(developer_fees_);
    bounty_amount_limit_lords.write(bounty_amount_limit_lords_);
    // write 2 arrays of Uint256 in storage_var (uint256 -> uint256)
    set_bounty_amount_limit_resources(
        amount_limit_resources_len,
        amount_limit_resources,
        token_ids_resources_len,
        token_ids_resources,
        0,
    );
    bounty_deadline_limit.write(bounty_deadline_limit_);
    return ();
}

func set_bounty_amount_limit_resources{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(amounts_len: felt, amounts: Uint256*, token_ids_len: felt, token_ids: Uint256*, index: felt) {
    alloc_locals;
    with_attr error_message("resources token id list not same length as resource amount list") {
        assert (amounts_len - token_ids_len) = 0;
    }
    if (index == amounts_len) {
        return ();
    }
    bounty_amount_limit_resources.write(token_ids[index], amounts[index]);
    set_bounty_amount_limit_resources(amounts_len, amounts, token_ids_len, token_ids, index + 1);
    return ();
}

// @notice Issues an bounty on the designated realm
// @param target_realm_id The target realm id
// @param bounty The bounty to be issued
@external
func issue_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: felt, bounty: Bounty
) -> (index: felt) {
    alloc_locals;
    // check that the owner of the bounty is the caller
    let (caller_address) = get_caller_address();
    with_attr error_message("bounty owner is not the caller of the contract") {
        assert caller_address = bounty.owner;
    }

    // check that target realm can still have an additional bounty added to them.
    let (count) = bounty_count.read(target_realm_id);
    let (local count_limit) = bounty_count_limit.read();
    let new_count = count + 1;

    // parse the bounty struct in order to check the type of bounty ($LORDS or resources),
    // the amount (and optionally the type of resource for the bounty) and the delay.
    let bounty_type = bounty.type;
    let (current_block) = get_block_number();

    // Check for valid delay and amount.
    // verify that amount is bigger than 0
    with_attr error_message("bounty amount negative or null") {
        assert_uint256_le(Uint256(0, 0), bounty.amount);
    }

    let (deadline_limit) = bounty_deadline_limit.read();
    let time = bounty.deadline - current_block;
    // verify that the delay is higher than the bounty_deadline_limit
    with_attr error_message("deadline not far enough in time") {
        assert is_le(deadline_limit, time) = 1;
    }

    let (lords_address) = lords_contract.read();
    let (erc1155_address) = erc1155_contract.read();
    let (contract_address) = get_contract_address();

    // transfer the amount from the caller to the mercenary contract
    if (bounty_type.is_lords == 1) {
        // check that the bounty amount is higher than the amount limit
        let (amount_limit) = bounty_amount_limit_lords.read();
        with_attr error_message("bounty amount lower than limit of {amount_limit}") {
            assert_uint256_le(amount_limit, bounty.amount);
        }

        IERC20.transferFrom(
            contract_address=lords_address,
            sender=caller_address,
            recipient=contract_address,
            amount=bounty.amount,
        );

        tempvar syscall_ptr = syscall_ptr;
        tempvar range_check_ptr = range_check_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
    } else {
        // TODO: to check but maybe don't limit the resource ids, if not exist, then will error anyway with transfer
        // with_attr error_message("ressource id does not exists") {
        //     assert_uint256_le(bounty_type.resource, Uint256(28, 0));
        //     assert_uint256_le(Uint256(1, 0), bounty_type.resource);
        // }

        // check that the bounty amount is higher than the amount limit
        let (amount_limit) = bounty_amount_limit_resources.read(bounty_type.resource);
        with_attr error_message("bounty amount lower than limit of {amount_limit}") {
            assert_uint256_le(amount_limit, bounty.amount);
        }

        let (data: felt*) = alloc();
        assert data[0] = 0;
        IERC1155.safeTransferFrom(
            contract_address=erc1155_address,
            _from=caller_address,
            to=contract_address,
            id=bounty_type.resource,
            amount=bounty.amount,
            data_len=1,
            data=data,
        );
        tempvar syscall_ptr = syscall_ptr;
        tempvar range_check_ptr = range_check_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
    }

    // add the bounty to the storage at current count and increment count
    // - go over all indices
    // - check if index < MAXIMUM_BOUNTIES_PER_REALM
    // - check if the spot is open at this index (nothing or deadline passed), if so write, if not continue
    let (index) = _add_bounty_to_storage(bounty, target_realm_id, count_limit, 0);
    bounty_count.write(target_realm_id, new_count);
    return (index=index);
}

func _add_bounty_to_storage{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_bounty: Bounty, target_realm_id: felt, bounty_count_limit: felt, index: felt
) -> (index: felt) {
    with_attr error_message("maximum number of bounties reached") {
        assert is_le(index, bounty_count_limit - 1) = 1;
    }

    let (current_bounty) = bounties.read(target_realm_id, index);
    let (current_block) = get_block_number();

    // if no bounty there or if the bounty's deadline is passed, put bounty there
    // TODO: better way to check if equal to zero
    if (current_bounty.amount.low == 0) {
        bounties.write(target_realm_id, index, new_bounty);
        return (index=index);
    }
    if (is_le(current_bounty.deadline, current_block) == 1) {
        bounties.write(target_realm_id, index, new_bounty);
        return (index=index);
    }

    return _add_bounty_to_storage(new_bounty, target_realm_id, bounty_count_limit, index + 1);
}

// @notice Claim the bounty on the target realm by performing combat on the
// @notice enemy realm
// @dev The attacking realm must have approved the empire contract before
// @dev calling hire_mercenary
// @param target_realm_id The target realm for the attack
// @param attacking_realm_id The id of the attacking realm
// @param attacking_army_id The id of the attacking army
@external
func hire_mercenary{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: felt, attacking_realm_id: felt, attacking_army_id: felt
) -> () {
    alloc_locals;
    // TODO check the target realm has bounties on it currently

    // let (caller) = get_caller_address();
    // let (empire) = get_contract_address();
    // let (local realm_contract_) = stacked_realm_contract.read();
    // let (lords_contract_) = lords_contract.read();

    // // temporarily transfer the command of the armies of the mercenary to the empire
    // IERC721.transferFrom(
    //     contract_address=realm_contract_,
    //     from_=caller,
    //     to=empire,
    //     tokenId=Uint256(attacking_realm_id, 0),
    // );

    // // attack the target of the bounty
    // let (combat_module_) = combat_module.read();
    // let (result) = ICombat.initiate_combat(
    //     contract_address=combat_module_,
    //     attacking_army_id=attacking_army_id,
    //     attacking_realm_id=Uint256(attacking_realm_id, 0),
    //     defending_army_id=0,
    //     defending_realm_id=Uint256(target_realm_id, 0),
    // );

    // // TODO update the reward distribution in order to distribute all rewards
    // // - go through all indices
    // // - sum total_bounty_amount
    // // - put value at index to 0;
    // // reward the total_bounty_amount and return the armies of the attacking realm
    // if (result == CCombat.COMBAT_OUTCOME_ATTACKER_WINS) {
    //     IERC20.transfer(
    //         contract_address=lords_contract_address, recipient=caller, amount=Uint256(bounty, 0)
    //     );
    //     bounties.write(target_realm_id, 0);
    //     tempvar syscall_ptr = syscall_ptr;
    //     tempvar pedersen_ptr = pedersen_ptr;
    //     tempvar range_check_ptr = range_check_ptr;
    // } else {
    //     tempvar syscall_ptr = syscall_ptr;
    //     tempvar pedersen_ptr = pedersen_ptr;
    //     tempvar range_check_ptr = range_check_ptr;
    // }

    // IERC721.transferFrom(
    //     contract_address=realm_contract_address,
    //     from_=empire,
    //     to=caller,
    //     tokenId=Uint256(attacking_realm_id, 0),
    // );

    return ();
}

//############
// RECEIVERS #
//############

@external
func onERC1155Received{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    operator: felt, _from: felt, id: Uint256, value: Uint256, data_len: felt, data: felt*
) -> (selector: felt) {
    return (ON_ERC1155_RECEIVED_SELECTOR,);
}
