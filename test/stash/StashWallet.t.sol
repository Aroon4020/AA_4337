// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {UserOperation} from "src/interfaces/UserOperation.sol";

import { StashedWallet } from "src/wallet/StashedWallet.sol";

import { StashedWalletFactory } from "src/wallet/StashedWalletFactory.sol";

import { StashedWalletProxy } from "src/wallet/StashedWalletProxy.sol";

import { Guardian } from "src/guardianModule/Guardian.sol";

import { EntryPoint } from "src/entrypoint/EntryPoint.sol";

import {MockSetter} from "../mock/MockSetter.sol";

import {MockStashedWalletV2} from "../mock/MockWalletV2.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockERC721} from "../mock/MockERC721.sol";
import {MockERC1155} from "../mock/MockERC1155.sol";
import {MockSignatureChecker} from "../mock/MockSignatureChecker.sol";
import {getUserOperation} from "./Fixtures.sol";
import {createSignature, createSignature2} from "test/utils/createSignature.sol";
import {ECDSA, SignatureChecker} from "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";


contract StashedWalletTest is Test {
    StashedWalletFactory factory;
    StashedWallet wallet;
    StashedWalletProxy proxy;
    EntryPoint entryPoint;
    Guardian guardian;
    MockStashedWalletV2 walletV2;
    MockERC20 erc20token;
    MockERC721 erc721token;
    MockERC1155 erc1155token;
    MockSetter setter;
    address ownerAddress = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    bytes32 salt;

    uint256 ownerPrivateKey =
        uint256(
            0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
        );
    function setUp() public {
        wallet = new  StashedWallet();
        factory = new StashedWalletFactory(address(wallet));
        entryPoint = new EntryPoint();
        guardian = new Guardian();
        setter = new MockSetter();
        salt = keccak256(abi.encodePacked(address(factory),address(entryPoint)));
        walletV2 = new MockStashedWalletV2();
        erc20token = new MockERC20();
        erc721token = new MockERC721("Token", "TKN");
        erc1155token = new MockERC1155();
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

    function testUpdateEntryPoint() public {
        StashedWallet proxyWallet = testDeployWallet();
        assertEq(address(proxyWallet.entryPoint()), address(entryPoint));
        address newEntryPoint = address(12);
        vm.prank(address(ownerAddress));
        proxyWallet.setEntryPoint(newEntryPoint);
        assertEq(address(proxyWallet.entryPoint()), address(newEntryPoint));
    }

    function testUpdateEntryPointNotOwner() public {
        StashedWallet proxyWallet = testDeployWallet();
        address newEntryPoint = address(12);
        address notOwner = address(13);
        vm.prank(address(notOwner));
        vm.expectRevert();
        proxyWallet.setEntryPoint(newEntryPoint);
        assertEq(address(proxyWallet.entryPoint()), address(entryPoint));
    }


    function testValidateUserOp() public {
        StashedWallet proxyWallet = testDeployWallet();
        assertEq(proxyWallet.nonce(), 0);

        (UserOperation memory userOp, bytes32 userOpHash) = getUserOperation(
            address(proxyWallet),
            proxyWallet.nonce(),
            abi.encodeWithSignature("setValue(uint256)", 1),
            address(entryPoint),
            uint8(block.chainid),
            ownerPrivateKey,
            vm
        );
        uint256 missingWalletFunds = 0;
        vm.prank(address(entryPoint));
        uint256 deadline = proxyWallet.validateUserOp(
            userOp,
            userOpHash,
            missingWalletFunds
        );
        assertEq(deadline, 0);
        assertEq(proxyWallet.nonce(), 1);
    }

    function testExecuteByEntryPoint() public {
        StashedWallet proxyWallet = testDeployWallet();
        assertEq(setter.value(), 0);

        bytes memory payload = abi.encodeWithSelector(
            setter.setValue.selector,
            1
        );

        vm.prank(address(entryPoint));
        proxyWallet.execute(address(setter), 0, payload);

        assertEq(setter.value(), 1);
    }

    function createBatchData()
        public
        view
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        address[] memory target = new address[](2);
        target[0] = address(setter);
        target[1] = address(setter);

        uint256[] memory values = new uint256[](2);
        values[0] = uint256(0);
        values[1] = uint256(0);

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSelector(setter.setValue.selector, 1);
        payloads[1] = abi.encodeWithSelector(setter.setValue.selector, 2);

        return (target, values, payloads);
    }


    function testExecuteBatchByEntryPoint() public {
        StashedWallet proxyWallet = testDeployWallet();
        assertEq(setter.value(), 0);

        (
            address[] memory target,
            uint256[] memory values,
            bytes[] memory payloads
        ) = createBatchData();

        vm.prank(address(entryPoint));
        proxyWallet.executeBatch(target, values, payloads);

        assertEq(setter.value(), 2);
    }

    function testExecuteBatchByOwner() public {
        StashedWallet proxyWallet = testDeployWallet();
        assertEq(setter.value(), 0);

        (
            address[] memory target,
            uint256[] memory values,
            bytes[] memory payloads
        ) = createBatchData();

        vm.prank(address(ownerAddress));
        proxyWallet.executeBatch(target, values, payloads);

        assertEq(setter.value(), 2);
    }


    function testPrefundEntryPoint() public {
        StashedWallet proxyWallet = testDeployWallet();
        vm.deal(address(proxyWallet), 1 ether);

        assertEq(proxyWallet.nonce(), 0);

        uint256 balanceBefore = address(entryPoint).balance;

        (UserOperation memory userOp, bytes32 digest) = getUserOperation(
            address(wallet),
            proxyWallet.nonce(),
            abi.encodeWithSignature("setValue(uint256)", 1),
            address(entryPoint),
            uint8(block.chainid),
            ownerPrivateKey,
            vm
        );

        uint256 missingWalletFunds = 0.001 ether;

        vm.prank(address(entryPoint));
        uint256 deadline = proxyWallet.validateUserOp(
            userOp,
            digest,
            missingWalletFunds
        );
        assertEq(deadline, 0);
        assertEq(proxyWallet.nonce(), 1);

        assertEq(
            address(entryPoint).balance,
            balanceBefore + missingWalletFunds
        );
    }


    function testTransferERC20() public {
        StashedWallet proxyWallet = testDeployWallet();
        MockERC20 token = new MockERC20();
        token.mint(address(proxyWallet), 1 ether);

        assertEq(token.balanceOf(address(entryPoint)), 0);

        vm.prank(address(ownerAddress));
        proxyWallet.transferERC20(address(token), address(entryPoint), 1 ether);

        assertEq(token.balanceOf(address(entryPoint)), 1 ether);
    }

    function testTransferERC20NotOwner() public {
        StashedWallet proxyWallet = testDeployWallet();
        MockERC20 token = new MockERC20();
        token.mint(address(proxyWallet), 1 ether);
        assertEq(token.balanceOf(address(entryPoint)), 0);
        address notOwner = address(13);
        vm.prank(address(notOwner));
        vm.expectRevert();
        proxyWallet.transferERC20(address(token), address(entryPoint), 1 ether);
        assertEq(token.balanceOf(address(entryPoint)), 0 ether);
    }

    function testTransferETH() public {
        StashedWallet proxyWallet = testDeployWallet(); 
        hoax(address(this), 1 ether);
        payable(address(proxyWallet)).call{value: 1 ether}("");

        assertEq(address(entryPoint).balance, 0);

        vm.prank(address(ownerAddress));
        proxyWallet.transferETH(payable(address(entryPoint)), 1 ether);

        assertEq(address(entryPoint).balance, 1 ether);
    }

    function testTransferETHNotOwner() public {
        StashedWallet proxyWallet = testDeployWallet();
        vm.deal(address(proxyWallet), 1 ether);

        assertEq(address(entryPoint).balance, 0);

        address notOwner = address(13);
        vm.prank(address(notOwner));
        vm.expectRevert();
        proxyWallet.transferETH(payable(address(entryPoint)), 1 ether);

        assertEq(address(entryPoint).balance, 0 ether);
    }


    function testSafeMintERC721ToWallet() public {
        StashedWallet proxyWallet = testDeployWallet();
        erc721token.safeMint(address(proxyWallet), 1237);

        assertEq(erc721token.ownerOf(1237), address(proxyWallet));
        assertEq(erc721token.balanceOf(address(proxyWallet)), 1);
    }

    function testSafeTransferERC721FromToWallet() public {
        StashedWallet proxyWallet = testDeployWallet();
        address from = address(0xABCD);

        erc721token.mint(from, 1237);

        vm.prank(from);
        erc721token.setApprovalForAll(address(this), true);

        erc721token.safeTransferFrom(from, address(proxyWallet), 1237);

        assertEq(erc721token.getApproved(1237), address(0));
        assertEq(erc721token.ownerOf(1237), address(proxyWallet));
        assertEq(erc721token.balanceOf(address(proxyWallet)), 1);
        assertEq(erc721token.balanceOf(from), 0);
    }

    function testSafeTransferERC721FromToWalletWithData() public {
        StashedWallet proxyWallet = testDeployWallet();
        address from = address(0xABCD);

        erc721token.mint(from, 1237);

        vm.prank(from);
        erc721token.setApprovalForAll(address(this), true);

        erc721token.safeTransferFrom(
            from,
            address(proxyWallet),
            1237,
            "testing 1237"
        );

        assertEq(erc721token.getApproved(1237), address(0));
        assertEq(erc721token.ownerOf(1237), address(proxyWallet));
        assertEq(erc721token.balanceOf(address(proxyWallet)), 1);
        assertEq(erc721token.balanceOf(from), 0);
    }

    function testTransferERC721FromWalletTo() public {
        StashedWallet proxyWallet = testDeployWallet();
        testSafeTransferERC721FromToWallet();

        address to = address(0xABCD);
        assertEq(erc721token.balanceOf(address(to)), 0);

        address target = address(erc721token);
        bytes memory payload = abi.encodeWithSelector(
            erc721token.transferFrom.selector,
            address(proxyWallet),
            to,
            1237
        );

        vm.prank(address(entryPoint));
        proxyWallet.execute(target, 0, payload);

        assertEq(erc721token.balanceOf(address(to)), 1);
        assertEq(erc721token.ownerOf(1237), address(to));
        assertEq(erc721token.balanceOf(address(proxyWallet)), 0);
    }

    function testBatchTransferERC721FromWalletTo() public {
        StashedWallet proxyWallet = testDeployWallet();
        testSafeTransferERC721FromToWallet();

        address from = address(0xABCD);
        erc721token.mint(from, 1238);

        vm.prank(from);
        erc721token.setApprovalForAll(address(this), true);
        erc721token.safeTransferFrom(from, address(proxyWallet), 1238);

        address to = address(0xABCD);
        assertEq(erc721token.balanceOf(address(to)), 0);
        assertEq(erc721token.ownerOf(1237), address(proxyWallet));
        assertEq(erc721token.ownerOf(1238), address(proxyWallet));
        assertEq(erc721token.balanceOf(address(proxyWallet)), 2);

        address[] memory target = new address[](2);
        target[0] = address(erc721token);
        target[1] = address(erc721token);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSelector(
            erc721token.transferFrom.selector,
            address(proxyWallet),
            to,
            1237
        );
        payloads[1] = abi.encodeWithSelector(
            erc721token.transferFrom.selector,
            address(proxyWallet),
            to,
            1238
        );
        uint256[] memory values = new uint256[](2);
        values[0] = uint256(0);
        values[1] = uint256(0);

        vm.prank(address(entryPoint));
        proxyWallet.executeBatch(target, values, payloads);

        assertEq(erc721token.balanceOf(address(to)), 2);
        assertEq(erc721token.ownerOf(1237), address(to));
        assertEq(erc721token.ownerOf(1238), address(to));
        assertEq(erc721token.balanceOf(address(proxyWallet)), 0);
    }

    function testMintERC1155ToWallet() public {
        StashedWallet proxyWallet = testDeployWallet();
        erc1155token.mint(address(proxyWallet), 1237, 1, "testing 123");

        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 1);
    }

    function testSafeTransferERC1155TFromToWallet() public {
        StashedWallet proxyWallet = testDeployWallet();
        address from = address(0xABCD);

        erc1155token.mint(from, 1237, 100, "");

        vm.prank(from);
        erc1155token.setApprovalForAll(address(this), true);

        erc1155token.safeTransferFrom(
            from,
            address(proxyWallet),
            1237,
            70,
            "testing 1237"
        );

        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 70);
        assertEq(erc1155token.balanceOf(from, 1237), 30);
    }

    function testTransferERC1155FromWalletTo() public {
        StashedWallet proxyWallet = testDeployWallet();
        testSafeTransferERC1155TFromToWallet();

        address to = address(0xCDEF);
        assertEq(erc1155token.balanceOf(address(to), 1237), 0);
        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 70);

        address target = address(erc1155token);
        bytes memory payload = abi.encodeWithSelector(
            erc1155token.safeTransferFrom.selector,
            address(proxyWallet),
            to,
            1237,
            40,
            "testing 1237"
        );

        vm.prank(address(entryPoint));
        proxyWallet.execute(target, 0, payload);

        assertEq(erc1155token.balanceOf(address(to), 1237), 40);
        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 30);
    }

    function testBatchTransferERC1155FromWalletTo() public {
        StashedWallet proxyWallet = testDeployWallet();
        testSafeTransferERC1155TFromToWallet();

        address to0 = address(0xCD);
        assertEq(erc1155token.balanceOf(address(to0), 1237), 0);
        address to1 = address(0xEF);
        assertEq(erc1155token.balanceOf(address(to1), 1237), 0);
        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 70);

        address[] memory target = new address[](2);
        target[0] = address(erc1155token);
        target[1] = address(erc1155token);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSelector(
            erc1155token.safeTransferFrom.selector,
            address(proxyWallet),
            to0,
            1237,
            35,
            "testing 1237"
        );
        payloads[1] = abi.encodeWithSelector(
            erc1155token.safeTransferFrom.selector,
            address(proxyWallet),
            to1,
            1237,
            35,
            "testing 1237"
        );
        uint256[] memory values = new uint256[](2);
        values[0] = uint256(0);
        values[1] = uint256(0);

        vm.prank(address(entryPoint));
        proxyWallet.executeBatch(target, values, payloads);

        assertEq(erc1155token.balanceOf(address(to0), 1237), 35);
        assertEq(erc1155token.balanceOf(address(to1), 1237), 35);
        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 0);
    }

    function testTransferERC721() public {
        StashedWallet proxyWallet = testDeployWallet();
        testSafeMintERC721ToWallet();

        assertEq(erc721token.balanceOf(address(proxyWallet)), 1);

        address to = address(0xCD);
        assertEq(erc721token.balanceOf(address(to)), 0);

        vm.prank(address(ownerAddress));
        proxyWallet.transferERC721(address(erc721token), 1237, to);

        assertEq(erc721token.balanceOf(address(to)), 1);
        assertEq(erc721token.ownerOf(1237), address(to));
    }

    function testTransferERC721NotOwner() public {
        StashedWallet proxyWallet = testDeployWallet();
        testSafeMintERC721ToWallet();

        assertEq(erc721token.balanceOf(address(proxyWallet)), 1);

        address to = address(0xCD);
        assertEq(erc721token.balanceOf(address(to)), 0);

        address notOwner = address(13);
        vm.prank(address(notOwner));
        vm.expectRevert();
        proxyWallet.transferERC721(address(erc721token), 1237, to);

        assertEq(erc721token.balanceOf(address(to)), 0);
        assertEq(erc721token.balanceOf(address(proxyWallet)), 1);
    }

    function testTransferERC1155() public {
        StashedWallet proxyWallet = testDeployWallet();
        testMintERC1155ToWallet();

        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 1);

        address to = address(0xCD);
        assertEq(erc1155token.balanceOf(address(to), 1237), 0);

        vm.prank(address(ownerAddress));
        proxyWallet.transferERC1155(address(erc1155token), 1237, to, 1);

        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 0);
        assertEq(erc1155token.balanceOf(address(to), 1237), 1);
    }

    function testTransferERC1155NotOwner() public {
        StashedWallet proxyWallet = testDeployWallet();
        testMintERC1155ToWallet();

        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 1);

        address to = address(0xCD);
        assertEq(erc1155token.balanceOf(address(to), 1237), 0);

        address notOwner = address(13);
        vm.prank(address(notOwner));
        vm.expectRevert();
        proxyWallet.transferERC1155(address(erc1155token), 1237, to, 1);

        assertEq(erc1155token.balanceOf(address(proxyWallet), 1237), 1);
        assertEq(erc1155token.balanceOf(address(to), 1237), 0);
    }

    function testAddAndWithdrawDeposit() public {
        StashedWallet proxyWallet = testDeployWallet();
        assertEq(proxyWallet.getDeposit(), 0);

        proxyWallet.addDeposit{value: 0.5 ether}();

        assertEq(proxyWallet.getDeposit(), 0.5 ether);

        address notOwner = address(12);
        vm.prank(address(notOwner));
        vm.expectRevert();
        proxyWallet.withdrawDepositTo(payable(address(ownerAddress)), 0.3 ether);
        assertEq(proxyWallet.getDeposit(), 0.5 ether);

        assertEq(address(notOwner).balance, 0);
        vm.startPrank(address(ownerAddress));
        vm.expectRevert();
        proxyWallet.withdrawDepositTo(payable(address(notOwner)), 0.51 ether);
        assertEq(proxyWallet.getDeposit(), 0.5 ether);

        proxyWallet.withdrawDepositTo(payable(address(notOwner)), 0.3 ether);
        assertEq(address(notOwner).balance, 0.3 ether);
        assertEq(proxyWallet.getDeposit(), 0.2 ether);
    }




    // function testIsValidSignature() public {
    //     StashedWallet proxyWallet = testDeployWallet();
    //     bytes32 messageHash = keccak256(abi.encode("Signed Message"));
    //     bytes memory signature = createSignature2(
    //         messageHash,
    //         ownerPrivateKey,
    //         vm
    //     );

    //     bool _sigValid = SignatureChecker.isValidSignatureNow(
    //         address(proxyWallet),
    //         ECDSA.toEthSignedMessageHash(messageHash),
    //         signature
    //     );

    //     assertEq(_sigValid, true);
    // }
    
    
    // function testIsValidSignatureNotOwner() public {
    //     // address notContractOwnerAddress = 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f; // anvil account (8)
    //     StashedWallet proxyWallet = testDeployWallet();
    //     uint256 notContractOwnerPrivateKey = uint256(
    //         0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97
    //     );
    //     bytes32 messageHash = keccak256(abi.encode("Signed Message"));

    //     bytes memory signature = createSignature2(
    //         messageHash,
    //         notContractOwnerPrivateKey,
    //         vm
    //     );

    //     bool _sigValid = SignatureChecker.isValidSignatureNow(
    //         address(proxyWallet),
    //         ECDSA.toEthSignedMessageHash(messageHash),
    //         signature
    //     );

    //     assertEq(_sigValid, false);
    // }
}    