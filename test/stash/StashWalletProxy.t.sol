// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import { StashedWallet } from "src/wallet/StashedWallet.sol";

import { StashedWalletFactory } from "src/wallet/StashedWalletFactory.sol";

import { StashedWalletProxy } from "src/wallet/StashedWalletProxy.sol";

import { Guardian } from "src/guardianModule/Guardian.sol";

import { EntryPoint } from "src/entrypoint/EntryPoint.sol";

import {MockStashedWalletV2} from "../mock/MockWalletV2.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockERC721} from "../mock/MockERC721.sol";




contract StashedWalletFactoryTest is Test {
    StashedWalletFactory factory;
    StashedWallet wallet;
    StashedWalletProxy proxy;
    EntryPoint entryPoint;
    Guardian guardian;
    MockStashedWalletV2 walletV2;
    MockERC20 erc20token;
    MockERC721 erc721token;
    address ownerAddress = address(12);
    bytes32 salt;

    function setUp() public{
        wallet = new  StashedWallet();
        factory = new StashedWalletFactory(address(wallet));
        entryPoint = new EntryPoint();
        guardian = new Guardian();
        salt = keccak256(abi.encodePacked(address(factory),address(entryPoint)));
        walletV2 = new MockStashedWalletV2();
        erc20token = new MockERC20();
        erc721token = new MockERC721("Token", "TKN");

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

    function testUpgradeWallet() public {
        StashedWallet proxyWallet = testDeployWallet();

        assertEq(address(proxyWallet.entryPoint()), address(entryPoint));
        assertEq(proxyWallet.owner(), ownerAddress);

        assertEq(address(entryPoint).balance, 0);

        vm.deal(address(proxyWallet), 1 ether);
        address notOwner = address(13);
        vm.prank(address(notOwner));
        vm.expectRevert();
        proxyWallet.transferETH(payable(address(entryPoint)), 1 ether);
        assertEq(address(entryPoint).balance, 0);

        vm.prank(address(ownerAddress));
        address impl = proxyWallet.UpgradeTo(address(walletV2));
        assertEq(impl,address(walletV2));
    }

    function testUpgradeWalletByEntryPoint() public {
        StashedWallet proxyWallet = testDeployWallet();

        assertEq(address(proxyWallet.entryPoint()), address(entryPoint));
        assertEq(proxyWallet.owner(), ownerAddress);

        assertEq(address(entryPoint).balance, 0);

        vm.deal(address(proxyWallet), 1 ether);

        vm.prank(address(entryPoint));
        address impl = proxyWallet.UpgradeTo(address(walletV2));
        assertEq(impl,address(walletV2));
    }

    function testProxyState() public {
        StashedWallet proxyWallet = testDeployWallet();

        assertEq(address(proxyWallet.entryPoint()), address(entryPoint));
        assertEq(proxyWallet.owner(), ownerAddress);

        assertEq(address(entryPoint).balance, 0);

        vm.deal(address(proxyWallet), 2 ether);
        assertEq(address(proxyWallet).balance, 2 ether);

        erc20token.mint(address(proxyWallet), 1 ether);
        assertEq(erc20token.balanceOf(address(proxyWallet)), 1 ether);

        erc721token.safeMint(address(proxyWallet), 1237);

        assertEq(address(proxyWallet).balance, 2 ether);
        assertEq(erc20token.balanceOf(address(proxyWallet)), 1 ether);
        assertEq(erc721token.ownerOf(1237), address(proxyWallet));
        assertEq(erc721token.balanceOf(address(proxyWallet)), 1);

        vm.prank(address(ownerAddress));
        // preUpgrade(proxyWallet);
        proxyWallet.UpgradeTo(address(walletV2));

        assertEq(address(proxyWallet.entryPoint()), address(entryPoint));
        assertEq(proxyWallet.owner(), ownerAddress);
        assertEq(address(proxyWallet).balance, 2 ether);
        assertEq(erc20token.balanceOf(address(proxyWallet)), 1 ether);
        assertEq(erc721token.ownerOf(1237), address(proxyWallet));
        assertEq(erc721token.balanceOf(address(proxyWallet)), 1);

        address to = address(0xABCD);
        vm.prank(address(ownerAddress));
        proxyWallet.transferETH(payable(address(entryPoint)), 1 ether);
        vm.startPrank(address(ownerAddress));
        proxyWallet.transferERC20(
            address(erc20token),
            address(entryPoint),
            1 ether
        );
        proxyWallet.transferERC721(address(erc721token), 1237, to);

        assertEq(address(proxyWallet).balance, 1 ether);
        assertEq(erc20token.balanceOf(address(proxyWallet)), 0);
        assertEq(erc721token.balanceOf(address(proxyWallet)), 0);
    }

}    