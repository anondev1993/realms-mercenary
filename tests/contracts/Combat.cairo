%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.alloc import alloc

@contract_interface
namespace IERC1155 {
    func safeBatchTransferFrom(
        _from: felt,
        to: felt,
        ids_len: felt,
        ids: Uint256*,
        amounts_len: felt,
        amounts: Uint256*,
        data_len: felt,
        data: felt*,
    ) {
    }
}

@storage_var
func combat_outcome() -> (outcome: felt) {
}

@storage_var
func resources_address() -> (address: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    outcome: felt, resources_address_: felt
) {
    combat_outcome.write(outcome);
    resources_address.write(resources_address_);

    return ();
}

@external
func initiate_combat{
    range_check_ptr, syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, bitwise_ptr: BitwiseBuiltin*
}(
    attacking_army_id: felt,
    attacking_realm_id: Uint256,
    defending_army_id: felt,
    defending_realm_id: Uint256,
) -> (combat_outcome: felt) {
    alloc_locals;
    let (resources_contract_address) = resources_address.read();
    let (contract_address) = get_contract_address();
    let (caller_address) = get_caller_address();

    let (ids: Uint256*) = alloc();
    assert ids[0] = Uint256(2, 0);
    assert ids[1] = Uint256(3, 0);

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = Uint256(1 * 10 ** 18, 0);
    assert amounts[1] = Uint256(1 * 10 ** 18, 0);

    let (data: felt*) = alloc();
    assert data[0] = 0;

    let (local outcome) = combat_outcome.read();
    if (outcome == 1) {
        IERC1155.safeBatchTransferFrom(
            contract_address=resources_contract_address,
            _from=contract_address,
            to=caller_address,
            ids_len=2,
            ids=ids,
            amounts_len=2,
            amounts=amounts,
            data_len=1,
            data=data,
        );
        tempvar range_check_ptr = range_check_ptr;
        tempvar syscall_ptr = syscall_ptr;
    } else {
        tempvar range_check_ptr = range_check_ptr;
        tempvar syscall_ptr = syscall_ptr;
    }
    return (combat_outcome=outcome);
}

@external
func set_combat_outcome{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _outcome: felt
) {
    combat_outcome.write(_outcome);
    return ();
}
