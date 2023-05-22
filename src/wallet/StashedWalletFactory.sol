// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/security/Pausable.sol";
import {Create2} from "openzeppelin-contracts/utils/Create2.sol";
import {StashedWallet} from "./StashedWallet.sol";
import {StashedWalletProxy} from "./StashedWalletProxy.sol";

/// @title StashedWalletFactory contract to deploy user smart wallets
contract StashedWalletFactory is Ownable, Pausable {
    address public immutable walletImplementation;

    error ZeroAddressProvided();

    constructor(address _walletImplementation, address _owner) Ownable() Pausable() {
        if (_walletImplementation == address(0) || _owner == address(0)) {
            revert ZeroAddressProvided();
        }

        walletImplementation = _walletImplementation;
    }

    /// @notice Deploy a smart wallet, with an entryPoint and Owner specified by the user
    ///         Intended that all wallets are deployed through this factory, so if no initCode is passed
    ///         then just returns the CREATE2 computed address
    function createWallet(
        address entryPoint,
        address walletOwner,
        uint32 upgradeDelay,
        bytes32 salt
    ) external whenNotPaused returns (StashedWallet) {
        address walletAddress = getWalletAddress(entryPoint, walletOwner, upgradeDelay, salt);

        // Determine if a wallet is already deployed at this address, if so return that
        uint256 codeSize = walletAddress.code.length;
        if (codeSize > 0) {
            return StashedWallet(payable(walletAddress));
        } else {
            // Deploy the wallet
            StashedWallet wallet = StashedWallet(payable(new StashedWalletProxy{salt: bytes32(salt)}(
                walletImplementation,
                abi.encodeCall(
                    StashedWallet.initialize,
                    (entryPoint, walletOwner, upgradeDelay)
                )))
            );

            return wallet;
        }
    }

    /// @notice Deterministically compute the address of a smart wallet using Create2
    function getWalletAddress(
        address entryPoint,
        address walletOwner,
        uint32 upgradeDelay,
        bytes32 salt
    ) public view returns (address) {
        bytes memory deploymentData = abi.encodePacked(
            type(StashedWalletProxy).creationCode,
            abi.encode(
                walletImplementation,
                abi.encodeCall(
                    StashedWallet.initialize,
                    (entryPoint, walletOwner, upgradeDelay)
                )
            )
        );

        return Create2.computeAddress(bytes32(salt), keccak256(deploymentData));
    }

    /// @notice Pause the StashedWalletFactory to prevent new wallet creation. OnlyOwner
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpause the StashedWalletFactory to allow new wallet creation. OnlyOwner
    function unpause() public onlyOwner {
        _unpause();
    }
}