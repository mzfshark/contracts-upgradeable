// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0-rc.0) (access/manager/AccessManaged.sol)

pragma solidity ^0.8.20;

import { IAuthorityUpgradeable } from "./IAuthorityUpgradeable.sol";
import { AuthorityUtilsUpgradeable } from "./AuthorityUtilsUpgradeable.sol";
import { IAccessManagerUpgradeable } from "./IAccessManagerUpgradeable.sol";
import { IAccessManagedUpgradeable } from "./IAccessManagedUpgradeable.sol";
import { ContextUpgradeable } from "../../utils/ContextUpgradeable.sol";
import "../../proxy/utils/Initializable.sol";

/**
 * @dev This contract module makes available a {restricted} modifier. Functions decorated with this modifier will be
 * permissioned according to an "authority": a contract like {AccessManager} that follows the {IAuthority} interface,
 * implementing a policy that allows certain callers to access certain functions.
 *
 * IMPORTANT: The `restricted` modifier should never be used on `internal` functions, judiciously used in `public`
 * functions, and ideally only used in `external` functions. See {restricted}.
 */
abstract contract AccessManagedUpgradeable is Initializable, ContextUpgradeable, IAccessManagedUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.AccessManaged
    struct AccessManagedStorage {
        address _authority;

        bool _consumingSchedule;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.AccessManaged")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AccessManagedStorageLocation = 0xf3177357ab46d8af007ab3fdb9af81da189e1068fefdc0073dca88a2cab40a00;

    function _getAccessManagedStorage() private pure returns (AccessManagedStorage storage $) {
        assembly {
            $.slot := AccessManagedStorageLocation
        }
    }

    /**
     * @dev Initializes the contract connected to an initial authority.
     */
    function __AccessManaged_init(address initialAuthority) internal onlyInitializing {
        __AccessManaged_init_unchained(initialAuthority);
    }

    function __AccessManaged_init_unchained(address initialAuthority) internal onlyInitializing {
        _setAuthority(initialAuthority);
    }

    /**
     * @dev Restricts access to a function as defined by the connected Authority for this contract and the
     * caller and selector of the function that entered the contract.
     *
     * [IMPORTANT]
     * ====
     * In general, this modifier should only be used on `external` functions. It is okay to use it on `public`
     * functions that are used as external entry points and are not called internally. Unless you know what you're
     * doing, it should never be used on `internal` functions. Failure to follow these rules can have critical security
     * implications! This is because the permissions are determined by the function that entered the contract, i.e. the
     * function at the bottom of the call stack, and not the function where the modifier is visible in the source code.
     * ====
     *
     * [NOTE]
     * ====
     * Selector collisions are mitigated by scoping permissions per contract, but some edge cases must be considered:
     *
     * * If the https://docs.soliditylang.org/en/v0.8.20/contracts.html#receive-ether-function[`receive()`] function
     * is restricted, any other function with a `0x00000000` selector will share permissions with `receive()`.
     * * Similarly, if there's no `receive()` function but a `fallback()` instead, the fallback might be called with
     * empty `calldata`, sharing the `0x00000000` selector permissions as well.
     * * For any other selector, if the restricted function is set on an upgradeable contract, an upgrade may remove
     * the restricted function and replace it with a new method whose selector replaces the last one, keeping the
     * previous permissions.
     * ====
     */
    modifier restricted() {
        _checkCanCall(_msgSender(), _msgData());
        _;
    }

    /**
     * @dev Returns the current authority.
     */
    function authority() public view virtual returns (address) {
        AccessManagedStorage storage $ = _getAccessManagedStorage();
        return $._authority;
    }

    /**
     * @dev Transfers control to a new authority. The caller must be the current authority.
     */
    function setAuthority(address newAuthority) public virtual {
        address caller = _msgSender();
        if (caller != authority()) {
            revert AccessManagedUnauthorized(caller);
        }
        if (newAuthority.code.length == 0) {
            revert AccessManagedInvalidAuthority(newAuthority);
        }
        _setAuthority(newAuthority);
    }

    /**
     * @dev Returns true only in the context of a delayed restricted call, at the moment that the scheduled operation is
     * being consumed. Prevents denial of service for delayed restricted calls in the case that the contract performs
     * attacker controlled calls.
     */
    function isConsumingScheduledOp() public view returns (bytes4) {
        AccessManagedStorage storage $ = _getAccessManagedStorage();
        return $._consumingSchedule ? this.isConsumingScheduledOp.selector : bytes4(0);
    }

    /**
     * @dev Transfers control to a new authority. Internal function with no access restriction. Allows bypassing the
     * permissions set by the current authority.
     */
    function _setAuthority(address newAuthority) internal virtual {
        AccessManagedStorage storage $ = _getAccessManagedStorage();
        $._authority = newAuthority;
        emit AuthorityUpdated(newAuthority);
    }

    /**
     * @dev Reverts if the caller is not allowed to call the function identified by a selector.
     */
    function _checkCanCall(address caller, bytes calldata data) internal virtual {
        AccessManagedStorage storage $ = _getAccessManagedStorage();
        (bool immediate, uint32 delay) = AuthorityUtilsUpgradeable.canCallWithDelay(
            authority(),
            caller,
            address(this),
            bytes4(data)
        );
        if (!immediate) {
            if (delay > 0) {
                $._consumingSchedule = true;
                IAccessManagerUpgradeable(authority()).consumeScheduledOp(caller, data);
                $._consumingSchedule = false;
            } else {
                revert AccessManagedUnauthorized(caller);
            }
        }
    }
}
