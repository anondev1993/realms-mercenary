%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.math import assert_le_felt, unsigned_div_rem, assert_not_zero
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
)
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_le,
    assert_uint256_le,
    assert_uint256_eq,
    uint256_add,
    uint256_eq,
    uint256_mul_div_mod,
    uint256_mul,
    uint256_unsigned_div_rem,
    uint256_sub,
)
from starkware.cairo.common.alloc import alloc

// Mercenary
from contracts.structures import Bounty, BountyType
from contracts.storage import (
    realm_contract,
    staked_realm_contract,
    erc1155_contract,
    lords_contract,
    combat_module,
    developer_fees_percentage,
    bounty_count_limit,
    bounty_amount_limit_lords,
    bounty_amount_limit_resources,
    bounty_deadline_limit,
    bounties,
    bounty_count,
    supportsInterface,
)
from contracts.constants import (
    DEVELOPER_FEES_PRECISION,
    ON_ERC1155_RECEIVED_SELECTOR,
    ON_ERC1155_BATCH_RECEIVED_SELECTOR,
)
from contracts.interface.ICombat import ICombat

// Openzeppelin
from cairo_contracts_git.src.openzeppelin.access.ownable.library import Ownable
from cairo_contracts_git.src.openzeppelin.token.erc721.IERC721 import IERC721
from cairo_contracts_git.src.openzeppelin.token.erc20.IERC20 import IERC20
// Realms
from realms_contracts_git.contracts.settling_game.utils.constants import CCombat
from realms_contracts_git.contracts.settling_game.interfaces.IERC1155 import IERC1155
from realms_contracts_git.contracts.settling_game.modules.resources.library import Resources
from realms_contracts_git.contracts.settling_game.interfaces.IRealms import IRealms

// TODO: add events
// TODO: get_external_contract_address, get_module_address

// -----------------------------------
// Mercenary Logic
// -----------------------------------

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt,
    realm_contract_: felt,
    staked_realm_contract_: felt,
    erc1155_contract_: felt,
    lords_contract_: felt,
    combat_module_: felt,
    developer_fees_percentage_: felt,
    bounty_count_limit: felt,
    bounty_amount_limit_lords_: Uint256,
    amount_limit_resources_len: felt,
    amount_limit_resources: Uint256*,
    token_ids_resources_len: felt,
    token_ids_resources: Uint256*,
    bounty_deadline_limit_: felt,
) {
    Ownable.initializer(owner);
    realm_contract.write(realm_contract_);
    staked_realm_contract.write(staked_realm_contract_);
    erc1155_contract.write(erc1155_contract_);
    lords_contract.write(lords_contract_);
    combat_module.write(combat_module_);
    with_attr error_message("developer fee percentage higher than 100%") {
        assert_le_felt(developer_fees_percentage_, DEVELOPER_FEES_PRECISION);
    }
    developer_fees_percentage.write(developer_fees_percentage_);
    bounty_amount_limit_lords.write(bounty_amount_limit_lords_);
    // write 2 arrays of Uint256 in storage_var (uint256 -> uint256)
    set_bounty_amount_limit_resources(
        amount_limit_resources_len,
        amount_limit_resources,
        token_ids_resources_len,
        token_ids_resources,
        0,
    );
    bounty_deadline_limit.write(bounty_deadline_limit_);
    return ();
}

func set_bounty_amount_limit_resources{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(amounts_len: felt, amounts: Uint256*, token_ids_len: felt, token_ids: Uint256*, index: felt) {
    alloc_locals;
    with_attr error_message("resources token id list not same length as resource amount list") {
        assert (amounts_len - token_ids_len) = 0;
    }
    if (index == amounts_len) {
        return ();
    }
    bounty_amount_limit_resources.write(token_ids[index], amounts[index]);
    set_bounty_amount_limit_resources(amounts_len, amounts, token_ids_len, token_ids, index + 1);
    return ();
}

// @notice Issues an bounty on the designated realm
// @param target_realm_id The target realm id
// @param bounty The bounty to be issued
@external
func issue_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: felt, bounty: Bounty
) -> (index: felt) {
    alloc_locals;
    // check that the owner of the bounty is the caller
    let (caller_address) = get_caller_address();
    with_attr error_message("bounty owner is not the caller of the contract") {
        assert caller_address = bounty.owner;
    }

    let (realm_contract_address) = realm_contract.read();
    // check that this realm exists
    let (realm_name) = IRealms.get_realm_name(realm_contract_address, Uint256(target_realm_id, 0));
    with_attr error_message("This realm does not exist") {
        assert_not_zero(realm_name);
    }

    // check that target realm can still have an additional bounty added to them.
    let (count) = bounty_count.read(target_realm_id);
    let (local count_limit) = bounty_count_limit.read();
    let new_count = count + 1;

    // parse the bounty struct in order to check the type of bounty ($LORDS or resources),
    // the amount (and optionally the type of resource for the bounty) and the delay.
    let bounty_type = bounty.type;
    let (current_block) = get_block_number();

    // Check for valid delay and amount.
    // verify that amount is bigger than 0
    with_attr error_message("bounty amount negative or null") {
        assert_uint256_le(Uint256(0, 0), bounty.amount);
    }

    let (deadline_limit) = bounty_deadline_limit.read();
    let time = bounty.deadline - current_block;
    // verify that the delay is higher than the bounty_deadline_limit
    with_attr error_message("deadline not far enough in time") {
        assert is_le(deadline_limit, time) = 1;
    }

    let (lords_address) = lords_contract.read();
    let (erc1155_address) = erc1155_contract.read();
    let (contract_address) = get_contract_address();

    // transfer the amount from the caller to the mercenary contract
    if (bounty_type.is_lords == 1) {
        // check that the bounty amount is higher than the amount limit
        let (amount_limit) = bounty_amount_limit_lords.read();
        with_attr error_message("bounty amount lower than limit of {amount_limit}") {
            assert_uint256_le(amount_limit, bounty.amount);
        }

        IERC20.transferFrom(
            contract_address=lords_address,
            sender=caller_address,
            recipient=contract_address,
            amount=bounty.amount,
        );

        tempvar syscall_ptr = syscall_ptr;
        tempvar range_check_ptr = range_check_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
    } else {
        // check that the bounty amount is higher than the amount limit
        let (amount_limit) = bounty_amount_limit_resources.read(bounty_type.resource);
        with_attr error_message("bounty amount lower than limit of {amount_limit}") {
            assert_uint256_le(amount_limit, bounty.amount);
        }

        let (data: felt*) = alloc();
        assert data[0] = 0;
        IERC1155.safeTransferFrom(
            contract_address=erc1155_address,
            _from=caller_address,
            to=contract_address,
            id=bounty_type.resource,
            amount=bounty.amount,
            data_len=1,
            data=data,
        );
        tempvar syscall_ptr = syscall_ptr;
        tempvar range_check_ptr = range_check_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
    }

    // add the bounty to the storage at current count and increment count
    // - go over all indices
    // - check if index < MAXIMUM_BOUNTIES_PER_REALM
    // - check if the spot is open at this index (nothing or deadline passed), if so write, if not continue
    let (index) = _add_bounty_to_storage(bounty, target_realm_id, count_limit, 0);
    bounty_count.write(target_realm_id, new_count);
    return (index=index);
}

// TODO: have a function to remove a bounty from the storage
func _add_bounty_to_storage{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_bounty: Bounty, target_realm_id: felt, bounty_count_limit: felt, index: felt
) -> (index: felt) {
    alloc_locals;
    with_attr error_message("maximum number of bounties reached") {
        assert is_le(index, bounty_count_limit - 1) = 1;
    }

    let (current_bounty) = bounties.read(target_realm_id, index);
    let (current_block) = get_block_number();
    let (lords_address) = lords_contract.read();
    let (erc1155_address) = erc1155_contract.read();
    let (contract_address) = get_contract_address();

    // if no bounty there or if the bounty's deadline is passed, put bounty there
    if (current_bounty.owner == 0) {
        bounties.write(target_realm_id, index, new_bounty);
        return (index=index);
    }

    let (data: felt*) = alloc();
    assert data[0] = 0;

    if (is_le(current_bounty.deadline, current_block) == 1) {
        // send back the money to the owner if deadline passed
        if (current_bounty.type.is_lords == 1) {
            IERC20.transfer(lords_address, current_bounty.owner, current_bounty.amount);
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            IERC1155.safeTransferFrom(
                erc1155_address,
                contract_address,
                current_bounty.owner,
                current_bounty.type.resource,
                current_bounty.amount,
                1,
                data,
            );
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }
        bounties.write(target_realm_id, index, new_bounty);
        return (index=index);
    }

    return _add_bounty_to_storage(new_bounty, target_realm_id, bounty_count_limit, index + 1);
}

// @notice Claim the bounty on the target realm by performing combat on the
// @notice enemy realm
// @dev The attacking realm must have approved the empire contract before
// @dev calling hire_mercenary
// @param target_realm_id The target realm for the attack
// @param attacking_realm_id The id of the attacking realm
// @param attacking_army_id The id of the attacking army
@external
func claim_bounties{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: felt,
    attacking_realm_id: felt,
    attacking_army_id: felt,
    defending_army_id: felt,
) -> () {
    alloc_locals;
    let (caller_address) = get_caller_address();
    let (contract_address) = get_contract_address();
    // check the target realm has bounties on it currently
    let (count) = bounty_count.read(target_realm_id);
    with_attr error_message("no bounties on this realm") {
        assert is_le(count, 0) = 1;
    }

    // DISCUSS: should you transfer from the staked realm or from the normal realm contract ?
    // DISCUSS: in modules (buildings, combat, ...) needs to be staked, will that stay ?
    // temporarily transfer the command of the armies of the mercenary to the mercenary contract
    let (s_realm_contract_address) = staked_realm_contract.read();
    IERC721.transferFrom(
        contract_address=s_realm_contract_address,
        from_=caller_address,
        to=contract_address,
        tokenId=Uint256(attacking_realm_id, 0),
    );

    // calculate all the resources and lords that the contract has
    let (old_balance_len, old_balance, resources_ids) = resources_balance(target_realm_id);

    // attack the target of the bounty
    let (combat_module_) = combat_module.read();
    let (result) = ICombat.initiate_combat(
        contract_address=combat_module_,
        attacking_army_id=attacking_army_id,
        attacking_realm_id=Uint256(attacking_realm_id, 0),
        defending_army_id=defending_army_id,
        defending_realm_id=Uint256(target_realm_id, 0),
    );

    // calculate all the resources and lords that the contract has
    let (_, new_balance, _) = resources_balance(target_realm_id);

    // reward the total_bounty_amount and return the armies of the attacking realm
    if (result == CCombat.COMBAT_OUTCOME_ATTACKER_WINS) {
        // calculate the amounts to be transferred then transfer
        transfer_bounties(target_realm_id);
        let (balance_difference: Uint256*) = alloc();

        let (data: felt*) = alloc();
        assert data[0] = 0;

        calculate_balance_difference(
            old_balance_len, old_balance, new_balance, balance_difference, 0
        );
        // send back the difference between them (what has been won from the battle)
        let (erc1155_address) = erc1155_contract.read();
        IERC1155.safeBatchTransferFrom(
            contract_address=erc1155_address,
            _from=contract_address,
            to=caller_address,
            ids_len=old_balance_len,
            ids=resources_ids,
            amounts_len=old_balance_len,
            amounts=balance_difference,
            data_len=1,
            data=data,
        );
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    IERC721.transferFrom(
        contract_address=s_realm_contract_address,
        from_=contract_address,
        to=caller_address,
        tokenId=Uint256(attacking_realm_id, 0),
    );

    return ();
}

// // test this
// func balance_difference{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
//     index: felt,
//     position: felt,
//     balance_len: felt,
//     old_balance: Uint256*,
//     new_balance: Uint256*,
//     diff_balance: Uint256*,
//     sparse_resources_ids: Uint256*,
//     resources_ids: Uint256*,
// ) -> () {
//     if (index == balance_len) {
//         return ();
//     }
//     let difference = Uint256(
//         new_balance.low - old_balance.low, new_balance.high - old_balance.high
//     );
//     // if not zero
//     let (balance_equal_zero) =
//     if (uint256_eq(difference, Uint256(0, 0)) == 0) {
//         assert diff_balance[index] = difference;
//         assert resources_ids[index] = sparse_resources_ids[position];
//         balance_difference(
//             index + 1,
//             position + 1,
//             balance_len,
//             old_balance,
//             new_balance,
//             diff_balance,
//             sparse_resources_ids,
//             resources_ids,
//         );
//     }

// balance_difference(
//         index + 1,
//         position,
//         balance_len,
//         old_balance,
//         new_balance,
//         diff_balance,
//         sparse_resources_ids,
//         resources_ids,
//     );
// }

func calculate_balance_difference{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    balance_len: felt,
    old_balance: Uint256*,
    new_balance: Uint256*,
    balance_difference: Uint256*,
    index: felt,
) -> () {
    if (balance_len == index) {
        return ();
    }
    let old_balance_token = old_balance[index];
    let new_balance_token = new_balance[index];
    let (diff) = uint256_sub(new_balance_token, old_balance_token);
    assert balance_difference[index] = diff;
    calculate_balance_difference(
        balance_len, old_balance, new_balance, balance_difference, index + 1
    );
    return ();
}

func resources_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: felt
) -> (len: felt, balance: Uint256*, resource_ids: Uint256*) {
    alloc_locals;
    let (realm_contract_address) = realm_contract.read();
    let (erc1155_address) = erc1155_contract.read();

    // resources ids
    let (local realms_data) = IRealms.fetch_realm_data(
        realm_contract_address, Uint256(target_realm_id, 0)
    );

    // array with some values 0, some other non null
    let (resources_ids: Uint256*) = Resources._calculate_realm_resource_ids(realms_data);

    let (owners: felt*) = alloc();

    let (contract_address) = get_contract_address();

    populate_resources_owner_list(
        account_address=contract_address,
        owners=owners,
        index=0,
        resources_len=realms_data.resource_number,
    );

    let (len, balance) = IERC1155.balanceOfBatch(
        contract_address=erc1155_address,
        owners_len=realms_data.resource_number,
        owners=owners,
        tokens_id_len=realms_data.resource_number,
        tokens_id=resources_ids,
    );

    return (len, balance, resources_ids);
}

func populate_resources_owner_list{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account_address: felt, owners: felt*, index: felt, resources_len: felt
) -> () {
    if (index == resources_len + 1) {
        return ();
    }
    assert owners[index] = account_address;
    return populate_resources_owner_list(account_address, owners, index + 1, resources_len);
}

func transfer_bounties{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: felt
) -> () {
    alloc_locals;
    let (caller_address) = get_caller_address();
    let (contract_address) = get_contract_address();

    let (local resources_ids: Uint256*) = alloc();
    let (local resources_amounts: Uint256*) = alloc();
    // calculate the sum of all the amounts for 1. lords 2. each resource token id
    let (count_limit) = bounty_count_limit.read();
    let lords = sum_lords(target_realm_id, 0, count_limit);

    let (lords_address) = lords_contract.read();
    let (erc1155_address) = erc1155_contract.read();

    // transfer if lords amount > 0,0
    let (lords_equal_to_zero) = uint256_eq(lords, Uint256(0, 0));

    with_attr error_message("lords bigger than what i have") {
        assert_uint256_le(lords, Uint256(100 * 10 ** 18, 0));
    }

    if (lords_equal_to_zero == 0) {
        // transfer all lords as once
        IERC20.transfer(contract_address=lords_address, recipient=caller_address, amount=lords);
        tempvar syscall_ptr = syscall_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    // transfer all resources as one batch transfer
    let resources_ids_len = collect_resources(
        resources_ids, resources_amounts, target_realm_id, 0, 0, count_limit
    );

    let (data: felt*) = alloc();
    assert data[0] = 0;

    // if the array has been populated, batch transfer
    if (is_le(resources_ids_len, 0) == 0) {
        IERC1155.safeBatchTransferFrom(
            contract_address=erc1155_address,
            _from=contract_address,
            to=caller_address,
            ids_len=resources_ids_len,
            ids=resources_ids,
            amounts_len=resources_ids_len,
            amounts=resources_amounts,
            data_len=1,
            data=data,
        );
        tempvar syscall_ptr = syscall_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    return ();
}

func collect_resources{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    resources_ids: Uint256*,
    resources_amounts: Uint256*,
    target_realm_id: felt,
    array_index: felt,
    index: felt,
    bounty_count_limit: felt,
) -> felt {
    alloc_locals;
    // bounty_count_limit
    if (index == bounty_count_limit) {
        return array_index;
    }
    let (bounty) = bounties.read(target_realm_id, index);
    let (fees_percentage) = developer_fees_percentage.read();
    local new_index;
    if (bounty.type.is_lords == 0) {
        assert resources_ids[array_index] = bounty.type.resource;
        // calculate the amount - the dev fees
        tempvar claimable_amount_percentage = 1 * DEVELOPER_FEES_PRECISION - fees_percentage;
        let (amount_without_fees, _) = uint256_mul(
            bounty.amount, Uint256(claimable_amount_percentage, 0)
        );
        let (amount_without_fees, _) = uint256_unsigned_div_rem(
            amount_without_fees, Uint256(DEVELOPER_FEES_PRECISION, 0)
        );
        assert resources_amounts[array_index] = amount_without_fees;
        assert new_index = array_index + 1;
        bounties.write(
            target_realm_id, index, Bounty(0, Uint256(0, 0), 0, BountyType(0, Uint256(0, 0)))
        );
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        assert new_index = array_index;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    return collect_resources(
        resources_ids, resources_amounts, target_realm_id, new_index, index + 1, bounty_count_limit
    );
}

func sum_lords{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: felt, index: felt, bounty_count_limit: felt
) -> Uint256 {
    if (index == bounty_count_limit) {
        let value = Uint256(0, 0);
        return value;
    }
    let sum_of_rest = sum_lords(target_realm_id, index + 1, bounty_count_limit);
    let (bounty) = bounties.read(target_realm_id, index);
    if (bounty.type.is_lords == 1) {
        let (sum, _) = uint256_add(sum_of_rest, bounty.amount);
        bounties.write(
            target_realm_id, index, Bounty(0, Uint256(0, 0), 0, BountyType(0, Uint256(0, 0)))
        );
        return sum;
    } else {
        return sum_of_rest;
    }
}

//############
// RECEIVERS #
//############

@external
func onERC1155Received{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    operator: felt, _from: felt, id: Uint256, value: Uint256, data_len: felt, data: felt*
) -> (selector: felt) {
    return (ON_ERC1155_RECEIVED_SELECTOR,);
}

@external
func onERC1155BatchReceived{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    operator: felt,
    _from: felt,
    ids_len: felt,
    ids: Uint256*,
    amounts_len: felt,
    amounts: Uint256*,
    data_len: felt,
    data: felt*,
) -> (selector: felt) {
    return (ON_ERC1155_BATCH_RECEIVED_SELECTOR,);
}
