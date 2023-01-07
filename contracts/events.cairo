%lang starknet

from contracts.structures import Bounty
from starkware.cairo.common.uint256 import Uint256

// ///////////////////
// EVENTS
// ///////////////////

// TODO: add event for the dev fees

@event
func bounty_issued(bounty: Bounty, target_realm_id: felt, index: felt) {
}

@event
func bounty_claimed(
    target_realm_id: felt,
    lords_amount: Uint256,
    token_ids_len: felt,
    token_ids: Uint256*,
    token_amounts_len: felt,
    token_amounts: Uint256*,
) {
}
