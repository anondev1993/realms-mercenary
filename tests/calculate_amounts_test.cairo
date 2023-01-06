%lang starknet
from starkware.cairo.common.uint256 import Uint256, assert_uint256_eq
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)
from starkware.cairo.common.alloc import alloc

from contracts.mercenary import issue_bounty, onERC1155Received
from contracts.library import MercenaryLib
from contracts.storage import supportsInterface, bounties
from contracts.structures import Bounty, BountyType

const MINT_AMOUNT = 100 * 10 ** 18;
const ACCOUNT1 = 1;
const REALM_CONTRACT = 121;
const S_REALM_CONTRACT = 122;
const COMBAT_MODULE = 123;
const BOUNTY_ISSUER = 124;
const BOUNTY_AMOUNT = 5 * 10 ** 18;
const TARGET_REALM_ID = 125;
const BOUNTY_COUNT_LIMIT = 50;
const BOUNTY_DEADLINE_LIMIT = 100;

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    // TODO: setup all the bounties (some lords, some resources)
    // TODO: debug this because there should be 100 ... lords but there are only 65 ...
    let (self_address) = get_contract_address();
    %{
        context.self_address = ids.self_address
        for i in range(0, 50):
            if (i <= 9):
                # 10 times
                # lords bounties
                store(context.self_address, "bounties", [ids.ACCOUNT1, ids.BOUNTY_AMOUNT, 0, 500, 1, 0, 0], [ids.TARGET_REALM_ID, i])
            if (i >= 10 and i < 40):
                # resource bounties
                store(context.self_address, "bounties", [ids.ACCOUNT1, ids.BOUNTY_AMOUNT, 0, 1000, 0, 1, 0], [ids.TARGET_REALM_ID, i])
            if (i>=40):
                # 10 times
                # resource bounties
                store(context.self_address, "bounties", [ids.ACCOUNT1, ids.BOUNTY_AMOUNT, 0, 1000, 1, 0, 0], [ids.TARGET_REALM_ID, i])
    %}
    return ();
}

@external
func test_sum_lords{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    with_attr error_message("bounty at index 0 not initialized") {
        let (bounty) = bounties.read(TARGET_REALM_ID, 0);
        assert_uint256_eq(bounty.amount, Uint256(BOUNTY_AMOUNT, 0));
    }

    let sum = MercenaryLib.sum_lords(TARGET_REALM_ID, 0, 50);

    // verify the total amount
    %{ assert ids.sum.low == 20 * ids.BOUNTY_AMOUNT, f'sum of lords bounty amount is equal to {ids.sum.low} but should be {20*ids.BOUNTY_AMOUNT}' %}

    with_attr error_message("bounty at index 0 not reset to 0") {
        let (bounty) = bounties.read(TARGET_REALM_ID, 0);
        assert_uint256_eq(bounty.amount, Uint256(0, 0));
    }

    return ();
}

@external
func test_sum_resources{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    alloc_locals;
    let (local resources_ids: Uint256*) = alloc();
    let (local resources_amounts: Uint256*) = alloc();

    with_attr error_message("bounty 12 not initialized") {
        let (bounty) = bounties.read(TARGET_REALM_ID, 12);
        assert_uint256_eq(bounty.amount, Uint256(BOUNTY_AMOUNT, 0));
    }

    let ids_len = MercenaryLib.collect_resources(
        resources_ids, resources_amounts, TARGET_REALM_ID, 0, 0, 50
    );

    with_attr error_message("wrong ids_len") {
        assert ids_len = 30;
    }

    with_attr error_message("bounty 12 not reset to 0") {
        let (bounty) = bounties.read(TARGET_REALM_ID, 12);
        assert_uint256_eq(bounty.amount, Uint256(0, 0));
    }

    with_attr error_message("resource id data did not fill correctly") {
        assert_uint256_eq(resources_ids[0], Uint256(1, 0));
        assert_uint256_eq(resources_ids[1], Uint256(1, 0));
        assert_uint256_eq(resources_ids[29], Uint256(1, 0));
    }

    with_attr error_message("resource amount data did not fill correctly") {
        assert_uint256_eq(resources_amounts[0], Uint256(BOUNTY_AMOUNT, 0));
        assert_uint256_eq(resources_amounts[1], Uint256(BOUNTY_AMOUNT, 0));
        assert_uint256_eq(resources_amounts[29], Uint256(BOUNTY_AMOUNT, 0));
    }

    return ();
}
