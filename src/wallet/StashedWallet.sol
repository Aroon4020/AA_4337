// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {IAccount} from "src/interfaces/IAccount.sol";
import {IEntryPoint} from "src/interfaces/IEntryPoint.sol";
import {UserOperation} from "src/interfaces/UserOperation.sol";
import {AccountStorage} from "src/utils/AccountStorage.sol";

import {Upgradeable} from "src/utils/Upgradeable.sol";
import {TokenCallbackHandler} from "src/callback/TokenCallbackHandler.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import {ECDSA, SignatureChecker} from "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import {Guardian} from "../guardianModule/Guardian.sol";
/// @title StashedWallet - Smart contract wallet compatible with ERC-4337
/// @dev This contract provides functionality to execute AA (ERC-4337) UserOperetion
///      It allows to receive and manage assets using the owner account of the smart contract wallet
contract StashedWallet is IAccount, Initializable, Upgradeable, TokenCallbackHandler{
    /// @notice All state variables are stored in AccountStorage.Layout with specific storage slot to avoid storage collision
    using AccountStorage for AccountStorage.Layout;

    /////////////////  EVENTS ///////////////

    event AccountInitialized(address indexed account, address indexed entryPoint, address owner, address guardianModule);
    event UpdateEntryPoint(address indexed newEntryPoint, address indexed oldEntryPoint);
    event PayPrefund(address indexed payee, uint256 amount);
    event OwnershipTransferred(address indexed sender, address indexed newOwner);
    event ReceivedETH(address indexed sender, uint256 indexed amount);
    event TransferedETH(address indexed to, uint256 amount);
    event TransferedERC20(address token, address indexed to, uint256 amount);
    event TransferedERC721(address indexed collection, uint256 indexed tokenId, address indexed to);
    event TransferedERC1155(address indexed collection, uint256 indexed tokenId, uint256 amount, address indexed to);

    /////////////////  MODIFIERS ///////////////

    /// @dev Only from EOA owner, or through the account itself (which gets redirected through execute())
    modifier onlyOwner() {
        if (msg.sender != owner() && msg.sender != address(this)) {
            revert("invalid owner");
        }
        _;
    }

    /// @notice Validate that only the entryPoint or Owner is able to call a method
    modifier onlyEntryPointOrOwner() {
        if (msg.sender != address(entryPoint()) && msg.sender != owner() && msg.sender != address(this)) {
            revert("invalid call");
        }
        _;
    }


    /// @dev This prevents initialization of the implementation contract itself
    constructor() {
        _disableInitializers();
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @notice Initialize function to setup the Stashed wallet contract
    /// @param  _entryPoint trused entrypoint
    /// @param  _owner wallet sign key address
    /// @param _guardianModule contract address that manages the guardains for wallet recovery
    function initialize(address _entryPoint, address _owner, address _guardianModule) public initializer {
        if (_entryPoint == address(0) || _owner == address(0)) {
            revert ("Zero Address");
        }

        AccountStorage.Layout storage layout = AccountStorage.layout();
        layout.entryPoint = IEntryPoint(_entryPoint);
        layout.owner = _owner;
        layout.guardianModule = _guardianModule;
        emit AccountInitialized(
            address(this),
            address(_entryPoint),
            _owner,
            _guardianModule
        );
    }

    /////////////////  FUNCTIONS ///////////////

    /// @dev This function is a special fallback function that is triggered when the contract receives Ether
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    /// @notice Returns the entryPoint address
    function entryPoint() public view returns (IEntryPoint) {
        return AccountStorage.layout().entryPoint;
    }

    /// @notice Returns the contract nonce
    function nonce() public view returns (uint256) {
        return AccountStorage.layout().nonce;
    }

    /// @notice Returns the contract owner
    function owner() public view returns (address) {
        return AccountStorage.layout().owner;
    }
    /// @notice Returns the guardianModule address
    function guardianModule() public view returns(address) {
        return AccountStorage.layout().guardianModule;
    }

    /// @notice Set the entrypoint contract, restricted to onlyOwner
    function setEntryPoint(address _newEntryPoint) external onlyOwner {
        if (_newEntryPoint == address(0)) revert("zero address");

        emit UpdateEntryPoint(_newEntryPoint, address(entryPoint()));

        AccountStorage.Layout storage layout = AccountStorage.layout();
        layout.entryPoint = IEntryPoint(_newEntryPoint);
    }

    /// @notice Validate that the userOperation is valid
    /// @param userOp - ERC-4337 User Operation
    /// @param userOpHash - Hash of the user operation, entryPoint address and chainId
    /// @param missingWalletFunds - Amount of ETH to pay the EntryPoint for processing the transaction
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingWalletFunds
    ) external override onlyEntryPointOrOwner returns (uint256 deadline) {
        // Validate signature
        _validateSignature(userOp, userOpHash);

        // UserOp may have initCode to deploy a wallet, in which case do not validate the nonce. Used in accountCreation
        if (userOp.initCode.length == 0) {
            // Validate and update the nonce storage variable - protect against replay attacks
            require(
                AccountStorage.layout().nonce++ == userOp.nonce,
                "StashedWallet: Invalid nonce"
            );
        }

        _prefundEntryPoint(missingWalletFunds);
        return 0;
    }

    /// @notice Method called by entryPoint or owner to execute the calldata supplied by a wallet
    /// @param target - Address to send calldata payload for execution
    /// @param value - Amount of ETH to forward to target
    /// @param payload - Calldata to send to target for execution
    function execute(address target, uint256 value, bytes calldata payload) external onlyEntryPointOrOwner {
        _call(target, value, payload);
    }

    /// @notice Execute a sequence of transactions, called directly by owner or by entryPoint
    function executeBatch(
        address[] calldata target,
        uint256[] calldata value,
        bytes[] calldata payload
    ) external onlyEntryPointOrOwner {
        if (target.length != payload.length || payload.length != value.length)
            revert("length mismatch");
        for (uint256 i; i < target.length; ) {
            _call(target[i], value[i], payload[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Transfer ownership by onlyGuardian
    function transferOwnership(address newOwner) public returns(address){
        AccountStorage.Layout storage layout = AccountStorage.layout();
        require(msg.sender == layout.guardianModule,"invalid call");
        
        layout.owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
        return newOwner;
    }

    /// @notice  upgrade the wallet
    function UpgradeTo(address newImplementation) external onlyEntryPointOrOwner  returns(address){
        _upgradeTo(newImplementation);
        return _getImplementation();
    }
    /////////////////  ASSETS MANAGER ///////////////

    /// @notice Transfer ETH out of the wallet. Permissioned to only the owner
    function transferETH(address payable to,uint256 amount) external onlyOwner {
        SafeTransferLib.safeTransferETH(to, amount);
        emit TransferedETH(to, amount);
    }

    /// @notice Transfer ERC20 tokens out of the wallet. Permissioned to only the owner
    function transferERC20(address token,address to,uint256 amount) external onlyOwner {
        SafeTransferLib.safeTransfer(ERC20(token), to, amount);
        emit TransferedERC20(token, to, amount);
    }

    /// @notice Transfer ERC721 tokens out of the wallet. Permissioned to only the owner
    function transferERC721(address collection, uint256 tokenId, address to) external onlyOwner {
        IERC721(collection).safeTransferFrom(address(this), to, tokenId);
        emit TransferedERC721(collection, tokenId, to);
    }

    /// @notice Transfer ERC1155 tokens out of the wallet. Permissioned to only the owner
    function transferERC1155(
        address collection,
        uint256 tokenId,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC1155(collection).safeTransferFrom(
            address(this),
            to,
            tokenId,
            amount,
            ""
        );
        emit TransferedERC1155(collection, tokenId, amount, to);
    }

    /////////////////  DEPOSITE MANAGER ///////////////

    /// @notice Returns the wallet's deposit in EntryPoint
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /// @notice Add to the deposite of the wallet in EntryPoint. Deposit is used to pay user gas fees
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    /// @notice Withdraw funds from the wallet's deposite in EntryPoint
    function withdrawDepositTo(
        address payable to,
        uint256 amount
    ) public onlyOwner {
        entryPoint().withdrawTo(to, amount);
    }

    /////////////////  INTERNAL METHODS ///////////////

    /// @notice Validate the signature of the userOperation
    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view {
        bytes32 messageHash = ECDSA.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(messageHash, userOp.signature);
        if (signer != owner()) revert("invalid signature");
    }

    /// @notice Pay the EntryPoint in ETH ahead of time for the transaction that it will execute
    ///         Amount to pay may be zero, if the entryPoint has sufficient funds or if a paymaster is used
    ///         to pay the entryPoint through other means
    /// @param amount - Amount of ETH to pay the entryPoint
    function _prefundEntryPoint(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        (bool success, ) = payable(address(entryPoint())).call{value: amount}(
            ""
        );
        require(success, "StashedWallet: ETH entrypoint payment failed");
        emit PayPrefund(address(this), amount);
    }

    /// @notice Perform and validate the function call
    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
