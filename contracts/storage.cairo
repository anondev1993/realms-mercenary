%lang starknet

from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.bool import TRUE, FALSE

from contracts.structures import Bounty
from contracts.constants import IERC1155_RECEIVER_ID

// -----------------------------------
// Contracts
// -----------------------------------

@storage_var
func realm_contract() -> (address: felt) {
}

@storage_var
func staked_realm_contract() -> (address: felt) {
}

@storage_var
func erc1155_contract() -> (address: felt) {
}

@storage_var
func lords_contract() -> (address: felt) {
}

@storage_var
func combat_module() -> (address: felt) {
}

// -----------------------------------
// Bounties
// -----------------------------------

@storage_var
func dev_fees_lords() -> (amount: Uint256) {
}

@storage_var
func dev_fees_resources(token_id: Uint256) -> (amount: Uint256) {
}

@storage_var
func developer_fees_percentage() -> (fees: felt) {
}

@storage_var
func bounty_count_limit() -> (limit: felt) {
}

@storage_var
func bounty_amount_limit_lords() -> (limit: Uint256) {
}

@storage_var
func bounty_amount_limit_resources(resources: Uint256) -> (limit: Uint256) {
}

@storage_var
func bounty_deadline_limit() -> (limit: felt) {
}

@storage_var
func bounties(realm_id: felt, index: felt) -> (bounty: Bounty) {
}

@storage_var
func bounty_count(realm_id: felt) -> (count: felt) {
}

// -----------------------------------
// Support Interfaces
// -----------------------------------
@view
func supportsInterface{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    interface_id: felt
) -> (success: felt) {
    if (interface_id == IERC1155_RECEIVER_ID) {
        return (success=TRUE);
    }
    return (success=FALSE);
}
