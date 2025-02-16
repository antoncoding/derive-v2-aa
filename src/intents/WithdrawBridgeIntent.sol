// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IntentExecutorBase} from "./IntentExecutorBase.sol";
import {ILightAccount} from "../interfaces/ILightAccount.sol";
import {LyraWithdrawWrapperV2New} from "../withdraw/LyraWithdrawWrapperV2New.sol";
/**
 * @title  WithdrawBridgeIntent
 * @notice A shared contract that allows authorized user to withdraw from LightAccount to off
 * @dev    Users who wish to have the auto-withdraw feature need to approve this contract to spend their tokens
 */
contract WithdrawBridgeIntent is IntentExecutorBase {
    
    IERC721 public immutable SUBACCOUNTS;
    LyraWithdrawWrapperV2New public immutable WITHDRAW_WRAPPER;

    /**
     * @notice The maximum fee for a token for single withdraw
     */
    mapping(address user => mapping(address token => uint256 maxFee)) public maxFee;

    error FeeTooHigh();

    event IntentWithdraw(
      address indexed scw, 
      address indexed token, 
      uint256 amount,
      address controller,
      address connector
    );

    event MaxFeeSet(address indexed user, address indexed token, uint256 maxFee);

    constructor(IERC721 _subaccounts) {
        SUBACCOUNTS = _subaccounts;
    }

    /**
     * @notice Execute a withdraw intent to auto bridge tokens off Derive.
     * @dev    The SCW must have approved this contract to spend the token, and set max fee for each token.
     * @param scw The light account address
     * @param token The ERC20 token address
     * @param amount The amount of tokens to withdraw
     * @param controller The Socket Controller address
     * @param connector The Socket Connector address
     */
    function executeWithdrawIntent(
      address scw,
      address token, 
      uint256 amount, 
      address controller, 
      address connector,
      uint256 gasLimit
    )
        external
        onlyIntentExecutor
    {
        
        IERC20(token).transferFrom(scw, address(this), amount);
        IERC20(token).approve(address(WITHDRAW_WRAPPER), amount);

        // The auto execution can only be triggered if the fee is less than the max fee set by the user
        uint256 feeInToken = WITHDRAW_WRAPPER.getFeeInToken(token, controller, connector, gasLimit);
        if (feeInToken > maxFee[scw][token]) revert FeeTooHigh();

        address recipient = ILightAccount(scw).owner();

        WITHDRAW_WRAPPER.withdrawToChain(
          token,
          amount,
          recipient,
          controller,
          connector,
          gasLimit
        );

        emit IntentWithdraw(scw, token, amount, controller, connector);
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
}
