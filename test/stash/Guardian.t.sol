// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {UserOperation} from "src/interfaces/UserOperation.sol";

import { StashedWallet } from "src/wallet/StashedWallet.sol";

import { StashedWalletFactory } from "src/wallet/StashedWalletFactory.sol";

import { StashedWalletProxy } from "src/wallet/StashedWalletProxy.sol";

import { Guardian } from "src/guardianModule/Guardian.sol";

import { EntryPoint } from "src/entrypoint/EntryPoint.sol";

contract GuardianTest {
    EntryPoint entryPoint;
    StashedWalletFactory factory;
    StashedWallet wallet;
    StashedWalletProxy proxy;
    Guardian guardian;

    address ownerAddress = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    bytes32 salt;
    address user = address(12);
    address notOwner = address(13);
    uint256 ownerPrivateKey =
        uint256(
            0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
        );
    function setUp() public {
        wallet = new  StashedWallet();
        factory = new StashedWalletFactory(address(wallet));
        entryPoint = new EntryPoint();
        guardian = new Guardian();
        salt = keccak256(abi.encodePacked(address(factory),address(entryPoint)));
        bytes memory data = abi.encodeCall(
            StashedWallet.initialize,
            (address(entryPoint), ownerAddress, address(guardian))
        );
        proxy = new StashedWalletProxy(address(wallet), data);
        salt = keccak256(abi.encodePacked(address(factory),address(entryPoint)));
    }

    function testDeployWallet() public  returns(StashedWallet proxyWallet){
        proxyWallet = factory.createWallet(
            address(entryPoint),
            ownerAddress,
            address(guardian),
            salt
        );
    }

    function testAddGuardians() public {
        StashedWallet proxyWallet = testDeployWallet();
    }

    
} 