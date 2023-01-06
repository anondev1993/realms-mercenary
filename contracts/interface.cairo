%lang starknet

from contracts.structures import Bounty

@contract_interface
namespace IMercenary {
    func claim_bounties(
        target_realm_id: felt,
        attacking_realm_id: felt,
        attacking_army_id: felt,
        defending_army_id: felt,
    ) -> () {
    }
    func remove_bounty(index: felt, target_realm_id: felt) -> () {
    }
    func issue_bounty(target_realm_id: felt, bounty: Bounty) -> (index: felt) {
    }
}
