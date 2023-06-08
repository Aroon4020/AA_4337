// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import { StashedWallet } from "src/wallet/StashedWallet.sol";

import { StashedWalletFactory } from "src/wallet/StashedWalletFactory.sol";

import { StashedWalletProxy } from "src/wallet/StashedWalletProxy.sol";

import { Guardian } from "src/guardianModule/Guardian.sol";

import { EntryPoint } from "src/entrypoint/EntryPoint.sol";
import {IEntryPoint} from "src/interfaces/IEntryPoint.sol";


contract StashedWalletFactoryTest is Test {
    StashedWalletFactory factory;
    StashedWallet wallet;
    EntryPoint entryPoint;
    Guardian guardian;
    address walletOwner = address(12);
    bytes32 salt;
    address ownerAddress = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955; // anvil account (7)
    uint256 ownerPrivateKey =
        uint256(0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356);
    EntryPoint newEntryPoint;
    address user = address(12);
    address notOwner = address(13);


    function setUp() public{
        wallet = new  StashedWallet();
        factory = new StashedWalletFactory(address(wallet));
        entryPoint = new EntryPoint();
        guardian = new Guardian();
        bytes memory data = abi.encodeCall(
            StashedWallet.initialize,
            (address(entryPoint), ownerAddress, address(guardian))
        );
        // bytes memory data = abi.encodeCall(
        //     wallet.initialize,
        //     (address(entryPoint), ownerAddress, upgradeDelay)
        // );
        salt = keccak256(abi.encodePacked(address(factory),address(entryPoint)));
    }

    function testDeployWallet() public {
        factory.createWallet(
            address(entryPoint),
            walletOwner,
            address(guardian),
            salt
        );
    }


    function testCreateWallet() public {
        address computedWalletAddress = factory.getWalletAddress(
            address(entryPoint),
            walletOwner,
            address(guardian),
            salt
        );

        StashedWallet proxyWallet = factory.createWallet(
            address(entryPoint),
            walletOwner,
            address(guardian),
            salt
        );

        assertEq(address(proxyWallet), computedWalletAddress);
        assertEq(address(proxyWallet.entryPoint()), address(entryPoint));
        assertEq(proxyWallet.owner(), walletOwner);
    }

    function testCreateWalletInCaseAlreadyDeployed() public {
        address walletAddress = factory.getWalletAddress(
            address(entryPoint),
            walletOwner,
            address(guardian),
            salt
        );
        // Determine if a wallet is already deployed at this address
        uint256 codeSize = walletAddress.code.length;
        assertTrue(codeSize == 0);

        wallet = factory.createWallet(
            address(entryPoint),
            walletOwner,
            address(guardian),
            salt
        );

        walletAddress = factory.getWalletAddress(
            address(entryPoint),
            walletOwner,
            address(guardian),
            salt
        );
        // Determine if a wallet is already deployed at this address
        codeSize = walletAddress.code.length;
        assertTrue(codeSize > 0);
        // Return the address even if the account is already deployed
        StashedWallet wallet2 = factory.createWallet(
            address(entryPoint),
            walletOwner,
            address(guardian),
            salt
        );

        assertEq(address(wallet), address(wallet2));
    }
}
 