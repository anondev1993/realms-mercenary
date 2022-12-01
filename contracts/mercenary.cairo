%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le

// Mercenary
from contracts.structures import Bounty
from contracts.storage import (
    realm_contract,
    stacked_realm_contract,
    erc1155_contract,
    lords_contract,
    combat_module,
    developer_fees,
    bounty_count_limit,
    bounty_amount_limit,
    bounty_deadline_limit,
    bounties,
    bounty_count,
)

// Openzeppelin
from cairo_contracts_git.src.openzeppelin.access.ownable.library import Ownable
from cairo_contracts_git.src.openzeppelin.token.erc721.IERC721 import IERC721
from cairo_contracts_git.src.openzeppelin.token.erc20.IERC20 import IERC20
// Realms
from realms_contracts_git.contracts.settling_game.utils.constants import CCombat

// -----------------------------------
// Mercenary Logic
// -----------------------------------

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt,
    realm_contract_: felt,
    stacked_realm_contract_: felt,
    erc1155_contract_: felt,
    lords_contract_: felt,
    combat_module_: felt,
    developer_fees_: felt,
) {
    Ownable.initializer(owner);
    realm_contract.write(realm_contract_);
    stacked_realm_contract.write(stacked_realm_contract_);
    erc1155_contract.write(erc1155_contract_);
    lords_contract.write(lords_contract_);
    combat_module.write(combat_module_);
    developer_fees.write(developer_fees_);
    return ();
}

// @notice Issues an bounty on the designated realm
// @param target_realm_id The target realm id
// @param bounty The bounty to be issued
@external
func issue_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: felt, bounty: Bounty
) {
    Ownable.assert_only_owner();
    // TODO check the target realm can still have an additional bounty added to them.
    let (count) = bounty_count.read(target_realm_id);
    let (limit) = bounty_limit.read();
    let is_under_limit = is_le(count, limit);
    with_attr error_message("bounty limit of {limit} for realm {target_realm_id} reached") {
        assert is_under_limit = 1;
    }
    // TODO parse the bounty struct in order to check the type of bounty ($LORDS or resources),
    // the amount (and optionally the type of resource for the bounty) and the delay. Check for
    // valid delay and amount.
    // TODO transfer the amount from the caller to the mercenary contract
    // TODO add the bounty to the storage at current count and increment count
    return ();
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
    // // reward the bounty and return the armies of the attacking realm
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
