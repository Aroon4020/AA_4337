// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {UserOperation} from "src/interfaces/UserOperation.sol";

import { StashedWallet } from "src/wallet/StashedWallet.sol";

import { StashedWalletFactory } from "src/wallet/StashedWalletFactory.sol";

import { StashedWalletProxy } from "src/wallet/StashedWalletProxy.sol";

import { Guardian } from "src/guardianModule/Guardian.sol";

import {IPaymaster} from "src/interfaces/IPaymaster.sol";

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
import {IEntryPoint} from "src/interfaces/IEntryPoint.sol";

import {TokenPaymaster } from "src/paymaster/TokenPaymaster.sol";
import {MockOracle} from "../mock/mockOracle.sol";
import {PriceOracle} from "src/paymaster/PriceOracle.sol";
import "../../lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
contract PaymasterUnitTest is Test {
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
    TokenPaymaster paymaster;
    PriceOracle priceoracle;
    MockOracle oracle;
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
        oracle = new MockOracle(); 
        priceoracle = new PriceOracle(AggregatorV3Interface(address(priceoracle)));
        paymaster = new TokenPaymaster(IEntryPoint(address(entryPoint)),ownerAddress,address(factory),ownerAddress,ownerAddress,ownerAddress);
        salt = keccak256(abi.encodePacked(address(factory),address(entryPoint)));
    }

    function testSetToken() public {
        address [] memory  token = new address[](1);//= address(erc20token);
        token[0] = address(erc20token);
        address [] memory  _priceoracle = new address[](1);//= address(erc20token);
        _priceoracle[0] = address(priceoracle);
        vm.expectRevert();
        paymaster.setToken(token,_priceoracle);
        vm.prank(ownerAddress);
        paymaster.setToken(token,_priceoracle);
    }

    function testDeposit() public {
        assertEq(address(entryPoint).balance, 0);
        assertEq(paymaster.getDeposit(), 0);
        hoax(address(ownerAddress), 1 ether);
        paymaster.deposit{value: 0.5 ether}();
        assertEq(address(entryPoint).balance, 0.5 ether);
        assertEq(paymaster.getDeposit(), 0.5 ether);
    }

    function testWithdraw() public {
        testDeposit();
        assertEq(address(entryPoint).balance, 0.5 ether);
        assertEq(address(user).balance, 0);
        vm.prank(address(ownerAddress));
        paymaster.withdrawTo(payable(address(user)), 0.3 ether);
        assertEq(address(user).balance, 0.3 ether);
    }


    function testWithdrawNotOwner() public {
        testDeposit();
        assertEq(address(entryPoint).balance, 0.5 ether);
        assertEq(address(user).balance, 0);
        vm.prank(address(notOwner));
        vm.expectRevert();
        paymaster.withdrawTo(payable(address(user)), 0.3 ether);
        assertEq(address(entryPoint).balance, 0.5 ether);
    }

    function testWithdrawToken() public {
        erc20token.mint(address(paymaster), 10 ether);
        vm.prank(ownerAddress);
        paymaster.withdrawToken(address(erc20token),10 ether);
        assertEq(erc20token.balanceOf(ownerAddress),10 ether);
    }

    function testAddStake() public {
        assertEq(paymaster.getDeposit(), 0);
        hoax(address(ownerAddress), 1 ether);
        paymaster.addStake{value: 0.5 ether}(120);
        console.log(paymaster.getStake());
        assertEq(paymaster.getStake(), 0.5 ether);
    }

    function testUnlockStake() public {
        testAddStake();
        assertEq(entryPoint.getDepositInfo(address(paymaster)).staked, true);
        assertEq(paymaster.getStake(), 0.5 ether);
        vm.prank(address(ownerAddress));
        paymaster.unlockStake();
        assertEq(entryPoint.getDepositInfo(address(paymaster)).staked, false);
    }

    function testUnlockStakeNotOwner() public {
        testAddStake();
        assertEq(paymaster.getStake(), 0.5 ether);

        hoax(address(notOwner), 1 ether);
        vm.expectRevert();
        paymaster.unlockStake();
    }

    function testWithdrawStake() public {
        assertEq(address(user).balance, 0);
        testUnlockStake();
        uint256 unstakeDelay = block.timestamp + 120;
        vm.warp(unstakeDelay + 200);
        vm.prank(address(ownerAddress));
        paymaster.withdrawStake(payable(address(user)));
        assertEq(address(user).balance, 0.5 ether);
    }

    function testWithdrawStakeNotOwner() public {
        assertEq(address(user).balance, 0);
        testUnlockStake();
        uint256 unstakeDelay = block.timestamp + 120;
        vm.warp(unstakeDelay + 200);
        hoax(address(notOwner), 1 ether);
        vm.expectRevert();
        paymaster.withdrawStake(payable(address(user)));
        assertEq(address(user).balance, 0);
    }


    function generateUserOp() public returns(UserOperation memory userOp) {
        UserOperation memory userOp;

        userOp = UserOperation({
            sender: address(wallet),
            nonce: wallet.nonce(),
            initCode: "",
            callData: "",
            callGasLimit: 2_000_000,
            verificationGasLimit: 3_000_000,
            preVerificationGas: 1_000_000,
            maxFeePerGas: 1_000_105_660,
            maxPriorityFeePerGas: 1_000_000_000,
            paymasterAndData: "",
            signature: ""
        });
    }
}