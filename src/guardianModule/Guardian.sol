// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {SignatureChecker} from "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
contract Guardian {

    uint256 constant delay = 86400;
    struct GuardianStorageEntry {
        // the list of guardians
        mapping(address => bytes) guardians;
        // recovery threshold
        uint256 threshold;
        // timedelay for adding and revoking of guardian
        uint256 timedelay;
    }

    // list of guardian detail against a wallet
    mapping (address => GuardianStorageEntry) internal entries;

    /// @notice add guardian for account recovery
    /// @param _guardian address of guardian
    /// @param _signature signature of for guardain agreeness verification
    function addGuardian(address _guardian, bytes calldata _signature) external {
        bytes32 dataHash = keccak256(abi.encodePacked(msg.sender));
        require(_guardian!=msg.sender,"caller is gaurdian");
        GuardianStorageEntry storage entry = entries[msg.sender];
        require(entry.timedelay<block.timestamp,"timedelay is not passed");
        require(SignatureChecker.isValidSignatureNow(_guardian, dataHash, _signature), "invalid guardian signature");
        require(bytes20(entry.guardians[_guardian]) == bytes32(0), "duplicate guardian");
        entry.guardians[_guardian] = _signature;
        entry.timedelay = block.timestamp + delay;
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
        for(uint256 i;i<_signatures.length;++i){
            require(bytes20(entry.guardians[_guardians[i]]) != bytes32(0), "not guardian");
            require(SignatureChecker.isValidSignatureNow(_guardians[i], dataHash, _signatures[i]), "invalid guardian signature");
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
        GuardianStorageEntry storage entry = entries[msg.sender];
        require(entry.timedelay<block.timestamp,"timedelay is not passed");
        require(_threshold>1,"zero threshold");
        entry.threshold = _threshold;
    }

}