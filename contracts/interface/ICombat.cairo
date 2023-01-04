%lang starknet
from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace ICombat {
    func initiate_combat(
        attacking_army_id: felt,
        attacking_realm_id: Uint256,
        defending_army_id: felt,
        defending_realm_id: Uint256,
    ) -> (combat_outcome: felt) {
    }
}
