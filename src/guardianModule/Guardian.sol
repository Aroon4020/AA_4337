// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {SignatureChecker} from "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
contract Guardian {

    struct GuardianStorageEntry {
        // the list of guardians
        mapping(address => bytes) guardians;
        // recovery threshold
        uint256 threshold;
    }

    // list of guardian detail against a wallet
    mapping (address => GuardianStorageEntry) internal entries;

        //.time delay
    /// @notice add guardian for account recovery
    /// @param _guardian address of guardian
    /// @param _signature signature of for guardain agreeness verification
    /// @param _threshold min threshold for recovery 
    function addGuardian(address _guardian, bytes calldata _signature, uint256 _threshold) external{
        bytes32 dataHash = keccak256(abi.encodePacked(msg.sender));
        require(_guardian!=msg.sender,"NMS");
        require(SignatureChecker.isValidSignatureNow(_guardian, dataHash, _signature), "Invalid Guardian Signature");
        GuardianStorageEntry storage entry = entries[msg.sender];
        require(bytes20(entry.guardians[_guardian]) == bytes32(0), "Duplicate Guardian");
        entry.guardians[_guardian] = _signature;
        if(_threshold>0){
            entry.threshold = _threshold;
        }
    }

    /// @notice recover wallet by calling changeOwner after guardian verification
    /// @param _wallet wallet to recover
    /// @param _guardians addresses of guardian
    /// @param _signatures signature signed by guardians indexed correctly acc to guardian address
    /// @param _newOwner new owner to set
    /// @param _data for calling transferOwnership(address newOwner)
    function recoverAccount(address _wallet, address [] calldata _guardians,bytes[] calldata _signatures, address _newOwner, bytes calldata _data) external  {
        GuardianStorageEntry storage entry = entries[_wallet];
        require(_guardians.length==_signatures.length,"length Mismatch");
        require(_signatures.length>=entry.threshold,"Min Threshold Require"); 
        require(_newOwner!=address(0),"Zero Address");
        bytes32 dataHash = keccak256(abi.encodePacked(_newOwner));
        for(uint256 i;i<_signatures.length;++i){
            require(bytes20(entry.guardians[_guardians[i]]) != bytes32(0), "Not Guardian");
            require(SignatureChecker.isValidSignatureNow(_guardians[i], dataHash, _signatures[i]), "Invalid Guardian Signature");
        }
        (,bytes memory returnData) = _wallet.call{value: 0}(_data);
        require(_newOwner==address(bytes20(returnData)),"Call Failed");
    }

    /// @notice revoke guardian
    /// @param _guardian address of guardian 

    function revokeGuardian(address _guardian) external {
        GuardianStorageEntry storage entry = entries[msg.sender];
        require(bytes20(entry.guardians[_guardian]) != bytes32(0), "Not Guardian Set");
        delete entry.guardians[_guardian];
    }

    /// @notice update threshold
    /// @param _threshold number for threshold
    function updateThreshold(uint256 _threshold) external {
        GuardianStorageEntry storage entry = entries[msg.sender];
        require(_threshold>0,"Zero Threshold");
        entry.threshold = _threshold;
    }

}