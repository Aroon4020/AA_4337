// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IEntryPoint.sol";
import "./Initializable.sol";


library AccountStorage {
    bytes32 private constant ACCOUNT_SLOT = keccak256("stashed.contracts.AccountStorage");
    struct Layout {
        
        IEntryPoint entryPoint;  
        address owner;       
        uint96 nonce;            
        uint256[50] __gap_0;

        Initializable.InitializableLayout initializableLayout;
        uint256[50] __gap_1;

        address guardianModule;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = ACCOUNT_SLOT;
        assembly {
            l.slot := slot
        }
    }
}