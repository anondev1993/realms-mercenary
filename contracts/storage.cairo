%lang starknet

from contracts.structures import Bounty

// -----------------------------------
// Main Storage
// -----------------------------------

@storage_var
func realm_contract() -> (address: felt) {
}

@storage_var
func stacked_realm_contract() -> (address: felt) {
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

@storage_var
func developer_fees() -> (fees: felt) {
}

// -----------------------------------
// Bounty Storage
// -----------------------------------

@storage_var
func bounty_count_limit() -> (limit: felt) {
}

@storage_var
func bounty_amount_limit() -> (limit: felt) {
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
