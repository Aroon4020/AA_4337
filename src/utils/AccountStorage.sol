// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/ILogicUpgradeControl.sol";
import "../interfaces/IEntryPoint.sol";
import "./Initializable.sol";

library AccountStorage {
    bytes32 private constant ACCOUNT_SLOT = keccak256("truewallet.contracts.AccountStorage");

    // struct RoleData {
    //     mapping(address => bool) members;
    //     bytes32 adminRole;
    // }

    struct Layout {


        /// ┌───────────────────┐
        /// │     base data     │
        IEntryPoint entryPoint;  // entryPoint
        address owner;           // owner slot
        uint96 nonce;            // explicit sizes of nonce, to fit a single storage cell with "owner"
        uint256[50] __gap_0;
        /// └───────────────────┘



        /// ┌───────────────────┐
        /// │   upgrade data    │
        ILogicUpgradeControl.UpgradeLayout logicUpgrade;         // LogicUpgradeControl.sol
        Initializable.InitializableLayout initializableLayout;
        uint256[50] __gap_1;
        /// └───────────────────┘

    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = ACCOUNT_SLOT;
        assembly {
            l.slot := slot
        }
    }
}