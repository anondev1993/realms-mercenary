%lang starknet

// starkware
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256

// mercenary
from contracts.structures import Bounty
from contracts.library import MercenaryLib
from contracts.storage import (
    developer_fees_percentage,
    bounty_count_limit,
    bounty_amount_limit_lords,
    bounty_amount_limit_resources,
    bounty_deadline_limit,
    bounties,
)

@view
func view_developer_fees_percentage{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> (developer_fees_percentage: felt) {
    let (developer_fees_percentage_) = developer_fees_percentage.read();
    return (developer_fees_percentage=developer_fees_percentage_);
}

@view
func view_bounty_count_limit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    bounty_count_limit: felt
) {
    let (bounty_count_limit_) = bounty_count_limit.read();
    return (bounty_count_limit=bounty_count_limit_);
}

@view
func view_bounty_amount_limit_lords{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> (bounty_amount_limit_lords: Uint256) {
    let (bounty_amount_limit_lords_) = bounty_amount_limit_lords.read();
    return (bounty_amount_limit_lords=bounty_amount_limit_lords_);
}

@view
func view_bounty_amount_limit_resources{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(resources: Uint256) -> (bounty_amount_limit_resources: Uint256) {
    let (bounty_amount_limit_resources_) = bounty_amount_limit_resources.read(resources);
    return (bounty_amount_limit_resources=bounty_amount_limit_resources_);
}

@view
func view_bounty_deadline_limit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> (bounty_deadline_limit: felt) {
    let (bounty_deadline_limit_) = bounty_deadline_limit.read();
    return (bounty_deadline_limit=bounty_deadline_limit_);
}

@view
func view_bounty{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(target_realm_id: Uint256, index: felt) -> (bounty: Bounty) {
    let (bounty_packed) = bounties.read(target_realm_id, index);
    let (bounty) = MercenaryLib.unpack_bounty(bounty_packed);
    return (bounty=bounty);
}
