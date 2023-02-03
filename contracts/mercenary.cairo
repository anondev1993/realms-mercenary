%lang starknet
// Starkware
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_le_felt, assert_not_zero
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
)
from starkware.cairo.common.uint256 import Uint256, assert_uint256_le, uint256_lt
from starkware.cairo.common.alloc import alloc

// Mercenary
from contracts.structures import Bounty, BountyType
from contracts.events import BountyIssued, DevFeesTransferred, BountyRemoved
from contracts.library import MercenaryLib
from contracts.storage import (
    developer_fees_percentage,
    bounty_count_limit,
    bounty_amount_limit_lords,
    bounty_amount_limit_resources,
    bounty_deadline_limit,
    bounties,
    bounty_count,
    dev_fees_lords,
)
from contracts.getters import (
    view_developer_fees_percentage,
    view_bounty_count_limit,
    view_bounty_amount_limit_lords,
    view_bounty_amount_limit_resources,
    view_bounty_deadline_limit,
    view_bounty,
    view_bounty_count,
)

from contracts.setters import (
    set_developer_fees_percentage,
    set_bounty_count_limit,
    set_bounty_amount_limit_lords,
    set_bounty_amount_limit_resources,
    set_bounty_deadline_limit,
)

from contracts.constants import (
    FEES_PRECISION,
    ON_ERC1155_RECEIVED_SELECTOR,
    ON_ERC1155_BATCH_RECEIVED_SELECTOR,
)
from contracts.interface.ICombat import ICombat

// Openzeppelin
from cairo_contracts_git.src.openzeppelin.access.ownable.library import Ownable
from cairo_contracts_git.src.openzeppelin.upgrades.library import Proxy
from cairo_contracts_git.src.openzeppelin.token.erc721.IERC721 import IERC721
from cairo_contracts_git.src.openzeppelin.token.erc20.IERC20 import IERC20
// Realms
from realms_contracts_git.contracts.settling_game.utils.constants import CCombat
from realms_contracts_git.contracts.settling_game.interfaces.IERC1155 import IERC1155
from realms_contracts_git.contracts.settling_game.modules.resources.library import Resources
from realms_contracts_git.contracts.settling_game.interfaces.IRealms import IRealms
from realms_contracts_git.contracts.settling_game.library.library_module import Module
from realms_contracts_git.contracts.settling_game.utils.game_structs import (
    ModuleIds,
    ExternalContractIds,
)

// -----------------------------------
// Mercenary Logic
// -----------------------------------

//
// Initialize & upgrade
//

// @notice Mercenary initializer
// @param owner Owner address
// @proxy_admin: Proxy admin address
// @param address_of_controller The address of the module controller
// @param developer_fees_percentage_ The developer fees percentage
// @param bounty_count_limit_ The max number of bounties on one realm at a time
// @param bounty_amount_limit_lords_ The minimum lords amount for a bounty
// @param bounty_deadline_limit_ The min lifetime of a bounty
// @param amount_limit_resources_len The length of min resources amount array
// @param amount_limit_resources The min amount for each resource
// @param token_ids_resources_len The length of resource ids array
// @param token_ids_resources The resource ids array

@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt,
    proxy_admin: felt,
    address_of_controller: felt,
    developer_fees_percentage_: felt,
    bounty_count_limit_: felt,
    bounty_amount_limit_lords_: Uint256,
    bounty_deadline_limit_: felt,
    amount_limit_resources_len: felt,
    amount_limit_resources: Uint256*,
    token_ids_resources_len: felt,
    token_ids_resources: Uint256*,
) {
    // DISCUSS: any reason to have a proxy_admin different from the owner?
    // DISCUSS: example: only realms team can upgrade modules
    // init proxy
    Proxy.initializer(proxy_admin);
    // init owner
    Ownable.initializer(owner);
    // init module controller
    Module.initializer(address_of_controller);
    // fees
    with_attr error_message("Developer fee percentage higher than 100%") {
        assert_le_felt(developer_fees_percentage_, FEES_PRECISION);
    }
    developer_fees_percentage.write(developer_fees_percentage_);
    bounty_count_limit.write(bounty_count_limit_);
    bounty_amount_limit_lords.write(bounty_amount_limit_lords_);
    bounty_deadline_limit.write(bounty_deadline_limit_);
    // write 2 arrays of Uint256 in storage_var (uint256 -> uint256)
    MercenaryLib.set_bounty_amount_limit_resources(
        amount_limit_resources_len,
        amount_limit_resources,
        token_ids_resources_len,
        token_ids_resources,
        0,
    );
    return ();
}

// @notice Set new proxy implementation
// @dev Can only be set by the proxy admin
// @param implementation: New implementation contract address
@external
func upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    implementation: felt
) -> () {
    Proxy.assert_only_admin();
    Proxy._set_implementation_hash(implementation);
    return ();
}

// @notice Issues a bounty on the designated realm
// @param target_realm_id The target realm id
// @param bounty The bounty to be issued
// @return index The index of the new bounty
@external
func issue_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: Uint256, bounty: Bounty
) -> (index: felt) {
    alloc_locals;
    // check that the owner of the bounty is the caller
    // DISCUSS: This is a double check to make sure that the bounty being placed is the right one
    // DISCUSS: not necessarily needed as we could fill bounty.owner ourselves
    let (caller_address) = get_caller_address();
    with_attr error_message("Bounty owner is not the caller of the contract") {
        assert caller_address = bounty.owner;
    }

    let (realm_contract_address) = Module.get_external_contract_address(ExternalContractIds.Realms);
    // check that this realm exists
    let (realm_name) = IRealms.get_realm_name(realm_contract_address, target_realm_id);
    with_attr error_message("This realm does not exist") {
        assert_not_zero(realm_name);
    }

    // check that target realm can still have an additional bounty added to them.
    let (count) = bounty_count.read(target_realm_id);
    let (local count_limit) = bounty_count_limit.read();

    // Check for valid delay and amount.
    // verify that amount is bigger than 0
    with_attr error_message("Bounty amount negative or null") {
        assert_uint256_le(Uint256(0, 0), bounty.amount);
    }

    // deadline_limit is an interval of blocks
    // minimum limit
    let (current_block) = get_block_number();
    let (deadline_limit) = bounty_deadline_limit.read();
    let time = bounty.deadline - current_block;
    // verify that the delay is higher than the bounty_deadline_limit
    with_attr error_message("Deadline not far enough in time") {
        assert is_le(deadline_limit, time) = 1;
    }

    let (lords_address) = Module.get_external_contract_address(ExternalContractIds.Lords);
    let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);
    let (contract_address) = get_contract_address();

    // transfer the amount from the caller to the mercenary contract
    if (bounty.type.is_lords == 1) {
        // check that the bounty amount is higher than the amount limit
        let (amount_limit) = bounty_amount_limit_lords.read();
        with_attr error_message("Bounty amount lower than limit of {amount_limit}") {
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
        let (amount_limit) = bounty_amount_limit_resources.read(bounty.type.resource_id);
        with_attr error_message("Bounty amount lower than limit of {amount_limit}") {
            assert_uint256_le(amount_limit, bounty.amount);
        }

        let (data: felt*) = alloc();
        IERC1155.safeTransferFrom(
            contract_address=erc1155_address,
            _from=caller_address,
            to=contract_address,
            id=bounty.type.resource_id,
            amount=bounty.amount,
            data_len=0,
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
    let (index) = MercenaryLib._add_bounty_to_storage(
        bounty,
        target_realm_id,
        count_limit,
        current_block,
        lords_address,
        erc1155_address,
        contract_address,
        0,
    );

    // emit event
    BountyIssued.emit(bounty=bounty, target_realm_id=target_realm_id, index=index);

    return (index=index);
}

// @notice Allows the owner of a bounty to remove it and transfer back the amount of the bounty
// @param index Index of the bounty
// @param target_realm_id Id of the target realm
@external
func remove_bounty{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index: felt, target_realm_id: Uint256
) -> () {
    alloc_locals;
    let (caller_address) = get_caller_address();
    let (contract_address) = get_contract_address();

    let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);
    let (lords_address) = Module.get_external_contract_address(ExternalContractIds.Lords);

    let (bounty) = bounties.read(target_realm_id, index);

    // assert that there is a bounty at that location
    with_attr error_message("No bounty on that index") {
        assert_not_zero(bounty.owner);
    }

    // assert that caller is the owner
    with_attr error_message("Only owner of the bounty can remove it") {
        assert bounty.owner = caller_address;
    }

    // transfer back the bounty
    MercenaryLib.transfer_back_bounty(
        lords_address, erc1155_address, contract_address, bounty.type, bounty.owner, bounty.amount
    );

    // decrement bounty counter
    MercenaryLib.decrease_bounty_count(target_realm_id);

    // set the bounty to 0 in the list
    bounties.write(
        target_realm_id, index, Bounty(0, Uint256(0, 0), 0, BountyType(0, Uint256(0, 0)))
    );

    // emit event
    BountyRemoved.emit(bounty=bounty, target_realm_id=target_realm_id, index=index);

    return ();
}

// @notice Claim the bounty on the target realm by performing combat on the
// @notice enemy realm
// @dev The attacking realm must have approved the transfer of his realm
// @dev to this contract before calling hire_mercenary
// @param target_realm_id The target realm id
// @param attacking_realm_id The id of the attacking realm
// @param attacking_army_id The id of the attacking army
// @param defending_army_id The id of the defending army
@external
func claim_bounties{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    target_realm_id: Uint256,
    attacking_realm_id: Uint256,
    attacking_army_id: felt,
    defending_army_id: felt,
) -> () {
    alloc_locals;
    let (caller_address) = get_caller_address();
    let (contract_address) = get_contract_address();
    // check the target realm has bounties on it currently
    let (count) = bounty_count.read(target_realm_id);
    with_attr error_message("No bounties on this realm") {
        assert is_le(count, 0) = 0;
    }

    // temporarily transfer the command of the armies of the mercenary to the mercenary contract
    let (s_realm_contract_address) = Module.get_external_contract_address(
        ExternalContractIds.S_Realms
    );
    IERC721.transferFrom(
        contract_address=s_realm_contract_address,
        from_=caller_address,
        to=contract_address,
        tokenId=attacking_realm_id,
    );

    // calculate all the resources and lords that the contract has
    let (old_balance_len, old_balance, resources_ids) = MercenaryLib.resources_balance(
        target_realm_id
    );

    // attack the target of the bounty
    // DISCUSS: will defending id will always be 0?
    let (combat_module_) = Module.get_module_address(ModuleIds.L06_Combat);
    let (result) = ICombat.initiate_combat(
        contract_address=combat_module_,
        attacking_army_id=attacking_army_id,
        attacking_realm_id=attacking_realm_id,
        defending_army_id=defending_army_id,
        defending_realm_id=target_realm_id,
    );

    // reward the total_bounty_amount and return the armies of the attacking realm
    if (result == CCombat.COMBAT_OUTCOME_ATTACKER_WINS) {
        // calculate all the resources and lords that the contract has
        let (_, new_balance, _) = MercenaryLib.resources_balance(target_realm_id);

        // calculate the amounts to be transferred then transfer
        MercenaryLib.transfer_bounties(target_realm_id);
        let (balance_difference: Uint256*) = alloc();

        let (data: felt*) = alloc();

        MercenaryLib.calculate_balance_difference(
            old_balance_len, old_balance, new_balance, balance_difference, 0
        );
        // send back the difference between them (what has been won from the battle)
        let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);
        IERC1155.safeBatchTransferFrom(
            contract_address=erc1155_address,
            _from=contract_address,
            to=caller_address,
            ids_len=old_balance_len,
            ids=resources_ids,
            amounts_len=old_balance_len,
            amounts=balance_difference,
            data_len=0,
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
        tokenId=attacking_realm_id,
    );

    return ();
}

// @notice Transfer the developer fees to any address
// @param destination_address The destination address for the fees
// @param resources_ids_len The length of the resources_ids array
// @param resources_ids The ids of the resources that need to be transferred
@external
func transfer_dev_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    destination_address: felt, resources_ids_len: felt, resources_ids: Uint256*
) -> () {
    alloc_locals;
    Ownable.assert_only_owner();
    // transfer lords
    let (lords_address) = Module.get_external_contract_address(ExternalContractIds.Lords);
    let (lords_amount) = dev_fees_lords.read();
    IERC20.transfer(lords_address, destination_address, lords_amount);

    // transfer resources
    let (dev_resources_amounts: Uint256*) = alloc();
    MercenaryLib.get_dev_resources_amounts(
        resources_ids_len, resources_ids, dev_resources_amounts, 0
    );

    let (erc1155_address) = Module.get_external_contract_address(ExternalContractIds.Resources);
    let (contract_address) = get_contract_address();

    let (data: felt*) = alloc();

    IERC1155.safeBatchTransferFrom(
        contract_address=erc1155_address,
        _from=contract_address,
        to=destination_address,
        ids_len=resources_ids_len,
        ids=resources_ids,
        amounts_len=resources_ids_len,
        amounts=dev_resources_amounts,
        data_len=0,
        data=data,
    );

    DevFeesTransferred.emit(
        destination_address=destination_address,
        dev_lords_amount=lords_amount,
        dev_resources_ids_len=resources_ids_len,
        dev_resources_ids=resources_ids,
        dev_resources_amounts_len=resources_ids_len,
        dev_resources_amounts=dev_resources_amounts,
    );

    return ();
}

//
// RECEIVERS
//

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
