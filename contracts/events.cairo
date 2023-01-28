%lang starknet

from contracts.structures import Bounty, CleanedBounty
from starkware.cairo.common.uint256 import Uint256

// ///////////////////
// EVENTS
// ///////////////////

@event
func BountyIssued(bounty: Bounty, target_realm_id: Uint256, index: felt) {
}

// TODO: refactor this find a better way to consolidate info (maybe one struct?)
@event
func BountiesClaimed(
    target_realm_id: Uint256,
    attacker_lords_amount: Uint256,
    dev_lords_amount: Uint256,
    resources_ids_len: felt,
    resources_ids: Uint256*,
    attacker_resources_amounts_len: felt,
    attacker_resources_amounts: Uint256*,
    dev_resources_amounts_len: felt,
    dev_resources_amounts: Uint256*,
) {
}

@event
func BountiesCleaned(
    target_realm_id: Uint256, cleaned_bounties_len: felt, cleaned_bounties: CleanedBounty*
) {
}

@event
func DevFeesTransferred(
    destination_address: felt,
    dev_lords_amount: Uint256,
    dev_resources_ids_len: felt,
    dev_resources_ids: Uint256*,
    dev_resources_amounts_len: felt,
    dev_resources_amounts: Uint256*,
) {
}
