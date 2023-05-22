// // SPDX-License-Identifier: GPL-3.0
// pragma solidity ^0.8.19;

// import { PRBTest } from "@prb/test/PRBTest.sol";
// import { console2 } from "forge-std/console2.sol";
// import { StdCheats } from "forge-std/StdCheats.sol";
// import {StashWalletFactory} from "../../src/StashWalletFactory.sol";
// import {StashWalletProxy} from "../../src/StashWalletProxy.sol";
// //import {impl} from "./StashWallet.t.sol";
// import {StashWallet} from "../../src/StashWallet.sol";
// contract StashWalletFactoryTest{
//     StashWallet impl;
//     StashWalletFactory factory;
//     address walletOwner = address(0x3);
//     address w = address(0x12);
//     address proxy;
//     function setUp() public {
//         impl =  new StashWallet();
//         factory = new StashWalletFactory(address(impl));
//     }

//     function test_CreateWalletProxy() public{
//         proxy = factory.deployProxy(address(impl),abi.encodeWithSignature("init(address)", walletOwner),"1");
//         //impl.check();
//         //StashWalletProxy(proxy).call(1 ether);
//         //StashWalletProxy(proxy).fallback.call(""){value}
//         //StashWalletProxy(proxy).call(bytes4(keccak256("init(address)")), walletOwner);
//         //StashWalletProxy(proxy).  
//         // (bool success, bytes memory data) = proxy.call{value: 0}(
//         //     abi.encodeWithSignature("init(address)", walletOwner)
//         // ); 
//     }

//     function test_callint() public {
//         (bool success, bytes memory data) = proxy.call(
//             abi.encodeWithSignature("init(address)", walletOwner)
//         );
//     }
// }
