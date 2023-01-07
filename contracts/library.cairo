%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
)
from starkware.cairo.common.uint256 import (
    Uint256,
    assert_uint256_le,
    uint256_add,
    uint256_eq,
    uint256_mul,
    uint256_unsigned_div_rem,
    uint256_sub,
)
from starkware.cairo.common.alloc import alloc

// Mercenary
from contracts.structures import Bounty, BountyType
from contracts.events import bounty_claimed
from contracts.storage import (
    realm_contract,
    erc1155_contract,
    lords_contract,
    developer_fees_percentage,
    bounty_amount_limit_resources,
    bounty_count_limit,
    bounties,
)
from contracts.constants import DEVELOPER_FEES_PRECISION

// Openzeppelin
from cairo_contracts_git.src.openzeppelin.token.erc20.IERC20 import IERC20
// Realms
from realms_contracts_git.contracts.settling_game.interfaces.IERC1155 import IERC1155
from realms_contracts_git.contracts.settling_game.modules.resources.library import Resources
from realms_contracts_git.contracts.settling_game.interfaces.IRealms import IRealms
from realms_contracts_git.contracts.settling_game.utils.game_structs import (
    ModuleIds,
    ExternalContractIds,
)
from realms_contracts_git.contracts.settling_game.library.library_module import Module

namespace MercenaryLib {
    // @notice Sets bounty_amount_limit_resources of token_ids(Uint256) -> amounts(Uint256)
    // @param amounts_len Length of the amounts array
    // @param amounts Amount for each resource token id
    // @param token_ids_len Length of the token ids array
    // @param token_ids array of token ids
    // @param index index for recursion
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
        set_bounty_amount_limit_resources(
            amounts_len, amounts, token_ids_len, token_ids, index + 1
        );
        return ();
    }

    // @notice Adds a bounty to the storage
    // @param new_bounty The new bounty
    // @param target_realm_id The target realm id
    // @param bounty_count_limit The max number of bounties on one realm at a time
    // @param index The index for recursion
    // @return index The index of the new bounty
    func _add_bounty_to_storage{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        new_bounty: Bounty, target_realm_id: felt, bounty_count_limit: felt, index: felt
    ) -> (index: felt) {
        alloc_locals;
        with_attr error_message("maximum number of bounties reached") {
            assert is_le(index, bounty_count_limit - 1) = 1;
        }

        let (current_bounty) = bounties.read(target_realm_id, index);
        let (current_block) = get_block_number();
        let (lords_address) = Module.get_external_contract_address(ExternalContractIds.Lords);
        let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);
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

    // @notice Calculate the difference in resource balance before
    // @notice and after combat
    // @param balance_len The length of old_balance and new_balance
    // @param old_balance The array of balances before combat
    // @param new_balance The array of balances after combat
    // @param balance_difference The array of balance differences
    // @parm index The index for recursion
    func calculate_balance_difference{
        syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
    }(
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

    // @notice Calculate resources balance of mercenary contract based on resources ids
    // @notice pillageable on specific target realm
    // @param target_realm_id The target realm id
    // @return len The length of the returned arrays
    // @return balance The balances of the resources ids for mercenary contract
    // @return resource_ids The resource ids pillageable on target realm
    func resources_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        target_realm_id: felt
    ) -> (len: felt, balance: Uint256*, resource_ids: Uint256*) {
        alloc_locals;
        let (realm_contract_address) = Module.get_external_contract_address(
            ExternalContractIds.Realms
        );
        let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);

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

    // @notice Creates an array of same owners with same length as resources_len
    // @param account_address The owner to repeatedly place in array
    // @param owners The array to be filled
    // @param index Index for recursion
    // @param resources_len The final length of the filled owners array
    func populate_resources_owner_list{
        syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
    }(account_address: felt, owners: felt*, index: felt, resources_len: felt) -> () {
        if (index == resources_len + 1) {
            return ();
        }
        assert owners[index] = account_address;
        return populate_resources_owner_list(account_address, owners, index + 1, resources_len);
    }

    // @notice If attacker wins transfers the bounties to him (lords and resources)
    // @param target_realm_id The target realm id
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

        let (lords_address) = Module.get_external_contract_address(ExternalContractIds.Lords);
        let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);

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

        // emit event
        bounty_claimed.emit(
            target_realm_id=target_realm_id,
            lords_amount=lords,
            token_ids_len=resources_ids_len,
            token_ids=resources_ids,
            token_amounts_len=resources_ids_len,
            token_amounts=resources_amounts,
        );
        return ();
    }

    // @notice Populates an array of resources amounts and ids of all resources bounties
    // @notice on a target realm and erases each bounty from the storage
    // @param resources_ids The array of resources ids of all bounties
    // @param resources_amounts The array of resources amounts of all bounties
    // @param target_realm_id The target realm id
    // @param array_index The current highest index of constructed arrays
    // @param index Index used for recursion
    // @param bounty_count_limit The max number of bounties on one realm at a time
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
            resources_ids,
            resources_amounts,
            target_realm_id,
            new_index,
            index + 1,
            bounty_count_limit,
        );
    }

    // @notice Sum total lords on all bounties of a target realm
    // @param target_realm_id The target realm id
    // @param index Index used for recursion
    // @param bounty_count_limit The max number of bounties on one realm at a time
    // @return Sum total lords
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
}