%lang starknet

from starkware.cairo.common.uint256 import Uint256

// -----------------------------------
// Structures
// -----------------------------------

struct BountyType {
    is_lords: felt,
    resource_id: Uint256,
}

// bounty type 0 = LORDS
// bounty type 1 = Resource
struct Bounty {
    owner: felt,
    amount: Uint256,
    deadline: felt,
    type: BountyType,
}
