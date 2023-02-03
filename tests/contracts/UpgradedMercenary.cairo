%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin

@storage_var
func bounty_count_limit() -> (limit: felt) {
}

@external
func increase_bounty_count_limit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> () {
    let (bounty_count_limit_) = bounty_count_limit.read();
    bounty_count_limit.write(bounty_count_limit_ + 1);
    return ();
}
