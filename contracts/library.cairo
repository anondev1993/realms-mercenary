%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import split_felt
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
)
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_lt,
    uint256_add,
    uint256_mul,
    uint256_unsigned_div_rem,
    uint256_sub,
)
from starkware.cairo.common.alloc import alloc

// Mercenary
from contracts.structures import Bounty, BountyType
from contracts.events import BountyClaimed
from contracts.storage import (
    developer_fees_percentage,
    bounty_amount_limit_resources,
    bounty_count_limit,
    bounty_count,
    bounties,
    dev_fees_lords,
    dev_fees_resources,
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
    // @notice Sets bounty_amount_limit_resources storage var of token_ids(Uint256) -> amounts(Uint256)
    // @param amounts_len Length of the amounts array
    // @param amounts Amount for each resource token id
    // @param token_ids_len Length of the token ids array
    // @param token_ids array of token ids
    // @param index index for recursion
    func set_bounty_amount_limit_resources{
        syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
    }(amounts_len: felt, amounts: Uint256*, token_ids_len: felt, token_ids: Uint256*, index: felt) {
        alloc_locals;
        with_attr error_message("Resources token id list not same length as resource amount list") {
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
        new_bounty: Bounty,
        target_realm_id: Uint256,
        bounty_count_limit: felt,
        current_block: felt,
        lords_address: felt,
        erc1155_address: felt,
        contract_address: felt,
        index: felt,
    ) -> (index: felt) {
        alloc_locals;
        with_attr error_message("Maximum number of bounties reached") {
            assert is_le(index, bounty_count_limit - 1) = 1;
        }

        let (current_bounty) = bounties.read(target_realm_id, index);

        // if no bounty there or if the bounty's deadline is passed, put bounty there
        if (current_bounty.owner == 0) {
            bounties.write(target_realm_id, index, new_bounty);
            // increase count here because there is a new bounty
            increase_bounty_count(target_realm_id);
            return (index=index);
        }

        if (is_le(current_bounty.deadline, current_block) == 1) {
            transfer_back_bounty(lords_address, erc1155_address, contract_address, current_bounty);
            // dont increase count here because we replace an existing bounty
            bounties.write(target_realm_id, index, new_bounty);
            return (index=index);
        }

        return _add_bounty_to_storage(
            new_bounty,
            target_realm_id,
            bounty_count_limit,
            current_block,
            lords_address,
            erc1155_address,
            contract_address,
            index + 1,
        );
    }

    // @notice transfer_back_bounty Transfers back the bounties a bounty to its owner
    // @param lords_address The address of the lords erc20 contract
    // @param erc1155_address The address of the resources erc1155 contract
    // @param contract_address The address of the mercenary contract
    // @param bounty The bounty
    func transfer_back_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        lords_address: felt, erc1155_address: felt, contract_address: felt, bounty: Bounty
    ) -> () {
        if (bounty.type.is_lords == 1) {
            // if lords
            IERC20.transfer(lords_address, bounty.owner, bounty.amount);
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            // if resources
            let (data: felt*) = alloc();
            IERC1155.safeTransferFrom(
                erc1155_address,
                contract_address,
                bounty.owner,
                bounty.type.resource_id,
                bounty.amount,
                0,
                data,
            );
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }
        return ();
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
        target_realm_id: Uint256
    ) -> (len: felt, balance: Uint256*, resource_ids: Uint256*) {
        alloc_locals;
        let (realm_contract_address) = Module.get_external_contract_address(
            ExternalContractIds.Realms
        );
        let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);

        // resources ids
        let (local realms_data) = IRealms.fetch_realm_data(realm_contract_address, target_realm_id);

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
        if (index == resources_len) {
            return ();
        }
        assert owners[index] = account_address;
        return populate_resources_owner_list(account_address, owners, index + 1, resources_len);
    }

    // @notice If attacker wins transfers the bounties to him (lords and resources)
    // @param target_realm_id The target realm id
    func transfer_bounties{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        target_realm_id: Uint256
    ) -> () {
        alloc_locals;
        // syscalls
        let (caller_address) = get_caller_address();
        let (contract_address) = get_contract_address();
        let (current_block) = get_block_number();

        // storage
        let (fees_percentage) = developer_fees_percentage.read();
        let (count_limit) = bounty_count_limit.read();

        // external contracts
        let (lords_address) = Module.get_external_contract_address(ExternalContractIds.Lords);
        let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);

        // create empty array
        let (local resources_ids: Uint256*) = alloc();
        let (local attacker_resources_amounts: Uint256*) = alloc();
        let (local dev_resources_amounts: Uint256*) = alloc();

        // go over all bounties
        // - to sum up amounts
        // - transfer back expired bounties to owner
        // - reset bounty to 0
        let (total_lords, resources_ids_len) = collect_tokens_and_transfer_back_expired(
            resources_ids=resources_ids,
            attacker_resources_amounts=attacker_resources_amounts,
            dev_resources_amounts=dev_resources_amounts,
            target_realm_id=target_realm_id,
            array_index=0,
            index=0,
            bounty_count_limit=count_limit,
            fees_percentage=fees_percentage,
            lords_address=lords_address,
            erc1155_address=erc1155_address,
            contract_address=contract_address,
            current_block=current_block,
        );

        // divide lords between attacker amount and dev amount
        let (attacker_lords, dev_lords) = divide_fees(total_lords, fees_percentage);
        // increment the current lords dev fees
        let (current_dev_lords) = dev_fees_lords.read();
        let (new_dev_lords, _) = uint256_add(current_dev_lords, dev_lords);
        dev_fees_lords.write(new_dev_lords);

        // transfer if lords amount > 0,0
        let (lords_sup_zero) = uint256_lt(Uint256(0, 0), attacker_lords);
        if (lords_sup_zero == 1) {
            // transfer all lords as once
            IERC20.transfer(
                contract_address=lords_address, recipient=caller_address, amount=attacker_lords
            );
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        let (data: felt*) = alloc();
        let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);
        // if the array has been populated, batch transfer
        if (is_le(0, resources_ids_len) == 1) {
            IERC1155.safeBatchTransferFrom(
                contract_address=erc1155_address,
                _from=contract_address,
                to=caller_address,
                ids_len=resources_ids_len,
                ids=resources_ids,
                amounts_len=resources_ids_len,
                amounts=attacker_resources_amounts,
                data_len=0,
                data=data,
            );
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        // reset bounty counter to 0
        bounty_count.write(target_realm_id, 0);

        // emit event
        BountyClaimed.emit(
            target_realm_id=target_realm_id,
            attacker_lords_amount=attacker_lords,
            dev_lords_amount=dev_lords,
            resources_ids_len=resources_ids_len,
            resources_ids=resources_ids,
            attacker_resources_amounts_len=resources_ids_len,
            attacker_resources_amounts=attacker_resources_amounts,
            dev_resources_amounts_len=resources_ids_len,
            dev_resources_amounts=dev_resources_amounts,
        );
        return ();
    }

    // @notice Goes over all bounties of a target realm to:
    // @notice - sum up the total lords amount
    // @notice - create an array of resource ids and amounts for both attacker and dev
    // @notice - transfer back the tokens in an expired bounty
    // @param resources_ids The array of resources ids of all bounties
    // @param attacker_resources_amounts The array of resources amounts going to attacker
    // @param dev_resources_amounts The array of resources amounts going to the developer
    // @param target_realm_id The target realm id
    // @param array_index The current highest index of constructed arrays
    // @param index Index used for recursion
    // @param bounty_count_limit The max number of bounties on one realm at a time
    // @param fees_percentage The fees percentage
    // @param lords_address The address of the lords erc20 contract
    // @param erc1155_address The address of the resources erc1155 contract
    // @param contract_address The address of the mercenary contract
    // @param current_block The current block
    // @return sum_of_lords Returns the total sum of lords in all bounties
    // @return resources_ids_len Returns the length of the resources_ids array
    func collect_tokens_and_transfer_back_expired{
        syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
    }(
        resources_ids: Uint256*,
        attacker_resources_amounts: Uint256*,
        dev_resources_amounts: Uint256*,
        target_realm_id: Uint256,
        array_index: felt,
        index: felt,
        bounty_count_limit: felt,
        fees_percentage: felt,
        lords_address: felt,
        erc1155_address: felt,
        contract_address: felt,
        current_block: felt,
    ) -> (sum_of_lords: Uint256, resources_ids_len: felt) {
        alloc_locals;
        // bounty_count_limit
        if (index == bounty_count_limit) {
            let sum_of_rest = Uint256(0, 0);
            return (sum_of_lords=sum_of_rest, resources_ids_len=array_index);
        }
        let (bounty) = bounties.read(target_realm_id, index);

        // if bounty is expired transfer back and don't sum
        if (is_le(bounty.deadline, current_block) == 1) {
            // transfer back bounty to owner
            transfer_back_bounty(lords_address, erc1155_address, contract_address, bounty);
            // reset bounty to 0
            bounties.write(
                target_realm_id, index, Bounty(0, Uint256(0, 0), 0, BountyType(0, Uint256(0, 0)))
            );
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;

            return collect_tokens_and_transfer_back_expired(
                resources_ids,
                attacker_resources_amounts,
                dev_resources_amounts,
                target_realm_id,
                array_index,
                index + 1,
                bounty_count_limit,
                fees_percentage,
                lords_address,
                erc1155_address,
                contract_address,
                current_block,
            );
        }

        // if "is_lords" is zero there is a bounty.owner, then it is a resource bounty
        local has_owner = is_not_zero(bounty.owner);
        if (has_owner == 0) {
            return collect_tokens_and_transfer_back_expired(
                resources_ids,
                attacker_resources_amounts,
                dev_resources_amounts,
                target_realm_id,
                array_index,
                index + 1,
                bounty_count_limit,
                fees_percentage,
                lords_address,
                erc1155_address,
                contract_address,
                current_block,
            );
        } else {
            if (bounty.type.is_lords == 1) {
                let (sum_of_rest, resources_ids_len) = collect_tokens_and_transfer_back_expired(
                    resources_ids,
                    attacker_resources_amounts,
                    dev_resources_amounts,
                    target_realm_id,
                    array_index,
                    index + 1,
                    bounty_count_limit,
                    fees_percentage,
                    lords_address,
                    erc1155_address,
                    contract_address,
                    current_block,
                );
                let (sum_of_rest, _) = uint256_add(sum_of_rest, bounty.amount);
                // reset bounty to 0
                bounties.write(
                    target_realm_id,
                    index,
                    Bounty(0, Uint256(0, 0), 0, BountyType(0, Uint256(0, 0))),
                );
                return (sum_of_lords=sum_of_rest, resources_ids_len=resources_ids_len);
            } else {
                assert resources_ids[array_index] = bounty.type.resource_id;
                // divide between attacker amount and dev amount
                let (attacker_fees, dev_fees) = divide_fees(bounty.amount, fees_percentage);
                assert dev_resources_amounts[array_index] = dev_fees;

                // increment the current lords dev fees
                let (current_dev_fees) = dev_fees_resources.read(bounty.type.resource_id);
                let (new_dev_fees, _) = uint256_add(current_dev_fees, dev_fees);
                dev_fees_resources.write(bounty.type.resource_id, new_dev_fees);

                assert attacker_resources_amounts[array_index] = attacker_fees;
                // reset bounty to 0
                bounties.write(
                    target_realm_id,
                    index,
                    Bounty(0, Uint256(0, 0), 0, BountyType(0, Uint256(0, 0))),
                );
                return collect_tokens_and_transfer_back_expired(
                    resources_ids,
                    attacker_resources_amounts,
                    dev_resources_amounts,
                    target_realm_id,
                    array_index + 1,
                    index + 1,
                    bounty_count_limit,
                    fees_percentage,
                    lords_address,
                    erc1155_address,
                    contract_address,
                    current_block,
                );
            }
        }
    }

    // @notice Increase the bounty count of a realm by 1
    // @param target_realm_id The target realm id
    func increase_bounty_count{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        target_realm_id: Uint256
    ) -> () {
        alloc_locals;
        let (bounty_count_) = bounty_count.read(target_realm_id);
        bounty_count.write(target_realm_id, bounty_count_ + 1);
        return ();
    }

    // @notice Decrease the bounty count of a realm by 1
    // @param target_realm_id The target realm id
    func decrease_bounty_count{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        target_realm_id: Uint256
    ) -> () {
        alloc_locals;
        let (bounty_count_) = bounty_count.read(target_realm_id);
        bounty_count.write(target_realm_id, bounty_count_ - 1);
        return ();
    }

    // @notice Converts a felt into Uint256
    // @param x The felt to convert
    // @return uint_x A Uint256
    func felt_to_uint256{range_check_ptr}(x: felt) -> (uint_x: Uint256) {
        let (high, low) = split_felt(x);
        return (Uint256(low=low, high=high),);
    }

    // @notice Divide the bounty amount between the attacker and the devs
    // @param bounty_amount The amount of the bounty
    // @param fees_percentage The fees percentage
    // @return attacker_fees The amount that goes to the attacker
    // @return dev_fees The amount that goes to the devs
    func divide_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        bounty_amount: Uint256, fees_percentage: felt
    ) -> (attacker_fees: Uint256, dev_fees: Uint256) {
        // convert felt DEVELOPER_FEES_PRECISION into uint
        // DISCUSS: better to have them directly as Uint256 ? we know they will always be max 10_000
        let (developer_fees_precision_uint) = felt_to_uint256(DEVELOPER_FEES_PRECISION);
        let (fees_percentage_uint) = felt_to_uint256(fees_percentage);
        let (dev_fees, _) = uint256_mul(bounty_amount, fees_percentage_uint);
        let (dev_fees, _) = uint256_unsigned_div_rem(dev_fees, developer_fees_precision_uint);
        let (attacker_fees) = uint256_sub(bounty_amount, dev_fees);
        return (attacker_fees=attacker_fees, dev_fees=dev_fees);
    }

    // @notice Populates an array with the amounts reserved for the devs for each resource id
    // @param resources_ids_len Lenght of array of resources ids
    // @param resources_ids Array of resources ids
    // @param resources_amounts Array of amounts
    // @param index Index for the recursion
    func get_dev_resource_amounts{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        resources_ids_len: felt, resources_ids: Uint256*, resources_amounts: Uint256*, index: felt
    ) -> () {
        if (index == resources_ids_len) {
            return ();
        }
        let (resource_amount) = dev_fees_resources.read(resources_ids[index]);
        assert resources_amounts[index] = resource_amount;
        get_dev_resource_amounts(resources_ids_len, resources_ids, resources_amounts, index + 1);
        return ();
    }
}
