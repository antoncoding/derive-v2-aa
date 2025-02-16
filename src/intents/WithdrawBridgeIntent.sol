// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IntentExecutorBase} from "./IntentExecutorBase.sol";
import {ILightAccount} from "../interfaces/ILightAccount.sol";
import {ISocketWithdrawWrapper} from "../interfaces/derive/ISocketWithdrawWrapper.sol";
import {IOFTWithdrawWrapper} from "../interfaces/derive/IOFTWithdrawWrapper.sol";

/**
 * @title  WithdrawBridgeIntent
 * @notice A shared contract that allows authorized user to withdraw from LightAccount to off
 * @dev    Users who wish to have the auto-withdraw feature need to approve this contract to spend their tokens
 */
contract WithdrawBridgeIntent is IntentExecutorBase {
    ISocketWithdrawWrapper public immutable SOCKET_BRIDGE;

    IOFTWithdrawWrapper public immutable IOFT_BRIDGE;

    /// @notice The maximum fee for a token for single withdraw
    mapping(address user => mapping(address token => uint256 maxFee)) public maxFee;

    
    /// @notice The valid recipients for the withdraw intent
    mapping(address user => mapping(address recipient => bool isValid)) public validRecipients;

    error InvalidRecipient();
    error FeeTooHigh();

    event IntentWithdrawSocket(
        address indexed scw,
        address indexed token,
        uint256 amount,
        address recipient,
        address controller,
        address connector
    );

    event IntentWithdrawLZ(
        address indexed scw, address indexed token, uint256 amount, address recipient, uint32 destEID
    );

    event MaxFeeSet(address indexed user, address indexed token, uint256 maxFee);

    event ValidRecipientSet(address indexed user, address indexed recipient, bool isValid);

    constructor(ISocketWithdrawWrapper _socketBridge, IOFTWithdrawWrapper _iOFTBridge) {
        SOCKET_BRIDGE = _socketBridge;
        IOFT_BRIDGE = _iOFTBridge;
    }

    /**
     * @notice Execute a withdraw intent to auto bridge tokens off Derive.
     * @dev    The SCW must have approved this contract to spend the token, and set max fee for each token.
     * @param scw The light account address
     * @param token The ERC20 token address
     * @param amount The amount of tokens to withdraw
     * @param recipient The recipient address, must be a valid recipient or the owner of the SCW
     * @param controller The Socket Controller address
     * @param connector The Socket Connector address
     */
    function executeWithdrawIntentSocket(
        address scw,
        address token,
        uint256 amount,
        address recipient,
        address controller,
        address connector,
        uint256 gasLimit
    ) external onlyIntentExecutor {
        IERC20(token).transferFrom(scw, address(this), amount);
        IERC20(token).approve(address(SOCKET_BRIDGE), amount);

        // The auto execution can only be triggered if the fee is less than the max fee set by the user
        uint256 feeInToken = SOCKET_BRIDGE.getFeeInToken(token, controller, connector, gasLimit);
        if (feeInToken > maxFee[scw][token]) revert FeeTooHigh();

        // The recipient must be pre-approved, or be the owner of the SCW
        if (!validRecipients[scw][recipient] && ILightAccount(scw).owner() != recipient) {
            revert InvalidRecipient();
        }

        SOCKET_BRIDGE.withdrawToChain(token, amount, recipient, controller, connector, gasLimit);

        emit IntentWithdrawSocket(scw, token, amount, recipient, controller, connector);
    }

    /**
     * @notice Execute a withdraw intent to auto bridge tokens off Derive through LayerZero OFT Wrapper.
     * @dev    The SCW must have approved this contract to spend the token, and set max fee for each token.
     * @param scw The light account address
     * @param token The ERC20 token address
     * @param amount The amount of tokens to withdraw
     * @param recipient The recipient address, must be a valid recipient or the owner of the SCW
     * @param destEID The destination EID
     */
    function executeWithdrawIntentLZ(address scw, address token, uint256 amount, address recipient, uint32 destEID)
        external
        onlyIntentExecutor
    {
        IERC20(token).transferFrom(scw, address(this), amount);
        IERC20(token).approve(address(IOFT_BRIDGE), amount);

        // The auto execution can only be triggered if the fee is less than the max fee set by the user
        uint256 feeInToken = IOFT_BRIDGE.getFeeInToken(token, amount, destEID);
        if (feeInToken > maxFee[scw][token]) revert FeeTooHigh();

        // The recipient must be pre-approved, or be the owner of the SCW
        if (!validRecipients[scw][recipient] && ILightAccount(scw).owner() != recipient) {
            revert InvalidRecipient();
        }

        IOFT_BRIDGE.withdrawToChain(token, amount, recipient, destEID);

        emit IntentWithdrawLZ(scw, token, amount, recipient, destEID);
    }

    /**
     * @notice Set the maximum fee for a token for single withdraw
     * @param token The token address
     * @param _maxFee The maximum fee for the withdraw bridge
     */
    function setMaxFee(address token, uint256 _maxFee) external {
        maxFee[msg.sender][token] = _maxFee;

        emit MaxFeeSet(msg.sender, token, _maxFee);
    }

    /**
     * @notice Set the valid recipient for all withdraw intent
     * @param recipient The recipient address
     */
    function setValidRecipient(address recipient, bool isValid) external {
        validRecipients[msg.sender][recipient] = isValid;

        emit ValidRecipientSet(msg.sender, recipient, isValid);
    }
}
