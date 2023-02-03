%lang starknet

// starkware
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_nn_le

// external libraries
from cairo_contracts_git.src.openzeppelin.access.ownable.library import Ownable

from contracts.structures import Bounty
from contracts.constants import FEES_PRECISION
from contracts.storage import (
    developer_fees_percentage,
    bounty_count_limit,
    bounty_amount_limit_lords,
    bounty_amount_limit_resources,
    bounty_deadline_limit,
    bounties,
)

// @notice Sets the percentage of developer fees
// @dev The fees percentage is limited to 10_000 (fee precision)
// @param Fees percentage
@external
func set_developer_fees_percentage{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    developer_fees_percentage_: felt
) -> () {
    Ownable.assert_only_owner();

    with_attr error_message("Developer fees too high") {
        assert_nn_le(developer_fees_percentage_, FEES_PRECISION);
    }

    developer_fees_percentage.write(developer_fees_percentage_);
    return ();
}

// @dev If you set the bounty count limit to a number smaller than the highest index
// @dev of a bounty on a target realm, then that bounty will never be claimable
// @dev but the owner will always be able to remove it and issue it again if he wants to.
// @dev Setting the bounty_count_limit to 0 actually allows us to pause the contract because
// @dev there are no more issuing and claiming.
@external
func set_bounty_count_limit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    bounty_count_limit_: felt
) -> () {
    Ownable.assert_only_owner();
    bounty_count_limit.write(bounty_count_limit_);
    return ();
}

@external
func set_bounty_amount_limit_lords{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    bounty_amount_limit_lords_: Uint256
) -> () {
    Ownable.assert_only_owner();
    bounty_amount_limit_lords.write(bounty_amount_limit_lords_);
    return ();
}

@external
func set_bounty_amount_limit_resources{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(resources: Uint256, bounty_amount_limit_resources_: Uint256) -> () {
    Ownable.assert_only_owner();
    bounty_amount_limit_resources.write(resources, bounty_amount_limit_resources_);
    return ();
}

@external
func set_bounty_deadline_limit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    bounty_deadline_limit_: felt
) -> () {
    Ownable.assert_only_owner();
    bounty_deadline_limit.write(bounty_deadline_limit_);
    return ();
}
