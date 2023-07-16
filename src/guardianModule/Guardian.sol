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

    /// @notice add guardian for account recovery
    /// @param _guardians address of guardian
    /// @param _signatures signature of for guardain agreeness verification
    function addGuardian(address [] calldata _guardians, bytes [] calldata _signatures, uint256 _threshold) external {
        //require(msg.sender.code.length>0,"Not SCW");
        require(_threshold>1,"threshold should be greater then zero");
        GuardianStorageEntry storage entry = entries[msg.sender];
        bytes32 dataHash  = keccak256(abi.encodePacked(msg.sender));
        for(uint256 i;i<_guardians.length;){
        require(_guardians[i]!=msg.sender,"caller is gaurdian");
        require(SignatureChecker.isValidSignatureNow(_guardians[i],dataHash, _signatures[i]), "invalid guardian signature");
        require(bytes20(entry.guardians[_guardians[i]]) == bytes32(0), "duplicate guardian"); 
        entry.guardians[_guardians[i]] = _signatures[i];    
            unchecked{
                ++i;
            }
        }
        entry.threshold = _threshold;
        
    }

    /// @notice recover wallet by calling changeOwner after guardian verification
    /// @param _wallet wallet to recover
    /// @param _guardians addresses of guardian
    /// @param _signatures signature signed by guardians indexed correctly acc to guardian address
    /// @param _newOwner new owner to set
    /// @param _data for calling transferOwnership(address newOwner)
    function recoverAccount(address _wallet, address [] calldata _guardians,bytes[] calldata _signatures, address _newOwner, bytes calldata _data) external  payable{
        GuardianStorageEntry storage entry = entries[_wallet];
        require(_guardians.length==_signatures.length,"length mismatch");
        require(_signatures.length>=entry.threshold,"min threshold require"); 
        require(_newOwner!=address(0),"zero address");
        require(_newOwner!=_wallet,"newOwner is same as previous owner");
        bytes32 dataHash = keccak256(abi.encodePacked(_newOwner));
        for(uint256 i;i<_signatures.length;){
            require(bytes20(entry.guardians[_guardians[i]]) != bytes32(0), "not guardian");
            require(SignatureChecker.isValidSignatureNow(_guardians[i], dataHash, _signatures[i]), "invalid guardian signature");
            unchecked{
                ++i;
            }
        }
        (,bytes memory returnData) = _wallet.call{value: msg.value}(_data);
        require(_newOwner==address(bytes20(returnData)),"call failed");
    }

    /// @notice revoke guardian
    /// @param _guardian address of guardian 
    function revokeGuardian(address _guardian) external {
        GuardianStorageEntry storage entry = entries[msg.sender];
        require(bytes20(entry.guardians[_guardian]) != bytes32(0), "guardian not set");
        delete entry.guardians[_guardian];
    }

    /// @notice update threshold
    /// @dev its open to dapp to call updatethreshhold through multicall or explicitly once certain set of guardian are set 
    /// @param _threshold number for threshold
    function updateThreshold(uint256 _threshold) external {
        require(_threshold>1,"threshold<1");
        GuardianStorageEntry storage entry = entries[msg.sender];
        require(entry.threshold>0,"threshold not set");
        entry.threshold = _threshold;
    }

}