%lang starknet

from starkware.cairo.common.uint256 import Uint256

// -----------------------------------
// Structures
// -----------------------------------

struct BountyType {
    is_lords: felt,
    resource: Uint256,
}

struct Bounty {
    owner: felt,
    amount: felt,
    deadline: felt,
    type: BountyType,
}
