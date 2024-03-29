%lang starknet

from contracts.structures import Bounty
from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IMercenary {
    func claim_bounties(
        target_realm_id: Uint256,
        attacking_realm_id: Uint256,
        attacking_army_id: felt,
        defending_army_id: felt,
    ) -> () {
    }
    func remove_bounty(index: felt, target_realm_id: Uint256) -> () {
    }
    func issue_bounty(target_realm_id: Uint256, bounty: Bounty) -> (index: felt) {
    }
    func transfer_dev_fees(
        destination_address: felt, resources_ids_len: felt, resources_ids: Uint256*
    ) -> () {
    }

    //
    // Getters
    //
    func view_developer_fees_percentage() -> (developer_fees_percentage: felt) {
    }

    func view_bounty_count_limit() -> (bounty_count_limit: felt) {
    }

    func view_bounty_amount_limit_lords() -> (bounty_amount_limit_lords: Uint256) {
    }

    func view_bounty_amount_limit_resources(resources: Uint256) -> (
        bounty_amount_limit_resources: Uint256
    ) {
    }
    func view_bounty_deadline_limit() -> (bounty_deadline_limit: felt) {
    }

    //
    // Setters
    //
    func set_developer_fees_percentage(developer_fees_percentage_: felt) -> () {
    }

    func set_bounty_count_limit(bounty_count_limit_: felt) -> () {
    }

    func set_bounty_amount_limit_lords(bounty_amount_limit_lords_: Uint256) -> () {
    }

    func set_bounty_amount_limit_resources(
        resources: Uint256, bounty_amount_limit_resources_: Uint256
    ) -> () {
    }

    func set_bounty_deadline_limit(bounty_deadline_limit_: felt) -> () {
    }
}
