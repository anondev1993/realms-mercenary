%lang starknet

from contracts.structures import Bounty
from starkware.cairo.common.uint256 import Uint256

// ///////////////////
// EVENTS
// ///////////////////

@event
func BountyIssued(bounty: Bounty, target_realm_id: Uint256, index: felt) {
}

@event
func BountyClaimed(
    target_realm_id: Uint256,
    lords_amount: Uint256,
    token_ids_len: felt,
    token_ids: Uint256*,
    attacker_token_amounts_len: felt,
    attacker_token_amounts: Uint256*,
    dev_token_amounts_len: felt,
    dev_token_amounts: Uint256*,
) {
}

@event
func DevFeesIncreased(is_lords: felt, resource_id: Uint256, added_amount: Uint256) {
}
