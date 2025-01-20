// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract CDP is Ownable, ERC20 {
    IPyth pyth;

    // A contract that allows users to deposit collateral and mints syntetic assets
    // Users can mint syntetic assets by depositing collateral
    // Users can redeem syntetic assets by burning them
    // Users can borrow syntetic assets by depositing collateral
    // users balances

    // Configuration
    uint256 public constant LIQUIDATION_THRESHOLD = 150;                        // 150% collateralization ratio
    uint256 public constant LIQUIDATION_BONUS = 10;                             // 10% bonus for liquidators
    address public pythContract = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729; // placeholder base sepolia
    // to do use oracle for price feeds
    uint256 public ETH_USDC_PRICE = 3000; // 1 ETH = 3000 USDC
    uint256 public COIN_USDC_PRICE = 270; // 1 COIN = 1000 USDC

    struct UserBalance {
        uint256 collateral;    // in ETH (wei)
        uint256 debt;          // in USD (with 18 decimals)
    }

    mapping(address => UserBalance) public balances;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event SynteticBorrowed(address indexed user, uint256 amount);
    event SynteticRepaid(address indexed user, uint256 amount);
    event PositionLiquidated(
        address indexed user,
        address indexed liquidator,
        uint256 reward
    );

    // errors
    error DepositFailed();
    error WithdrawalFailed();
    error InsufficientCollateral();
    error PositionNotLiquidatable();
    error InvalidAmount();
    error InsufficientSynteticAssets();
    constructor() Ownable(msg.sender) ERC20("Coinbase", "COIN") {
        pyth = IPyth(pythContract);
    }

    // deposit collateral
    function depositCollateral(uint256 amount) public payable {
        balances[msg.sender].collateral += amount;
        if (msg.value != amount) revert DepositFailed();
        emit CollateralDeposited(msg.sender, amount);

    }

    // withdraw collateral
    function withdrawCollateral(uint256 amount) public {
        balances[msg.sender].collateral -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert WithdrawalFailed();
        emit CollateralWithdrawn(msg.sender, amount);
    }

    // Calculate the collateralization ratio (in percent)
    function getCollateralRatio(address user) public view returns (uint256) {
        UserBalance memory position = balances[user];
        if (position.debt == 0) return type(uint256).max;
        
        uint256 collateralValue = (position.collateral * ETH_USDC_PRICE); // 1 ether * 3000
        uint256 debtValue = (position.debt * COIN_USDC_PRICE);            // 0.2 ether (2e17) * 260
        console.log("collateralValue", collateralValue);
        console.log("debtValue", debtValue);
        console.log("ratio", (collateralValue * 100) / debtValue);        // 150000
        return (collateralValue * 100) / debtValue;
    }

    // Check if a position can be liquidated
    function isLiquidatable(address user) public view returns (bool) {
        return getCollateralRatio(user) < LIQUIDATION_THRESHOLD;
    }

    // deposit and borrow syntetic assets
    function depositAndBorrowSyntetic(uint256 amountDeposit, uint256 amountBorrow) public {
        depositCollateral(amountDeposit);
        borrowSyntetic(amountBorrow);
    }

    // Modified borrow function with collateral check
    function borrowSyntetic(uint256 amount) public {
        if (amount == 0) revert InvalidAmount();
        
        UserBalance storage position = balances[msg.sender];
        position.debt += amount;
        
        // Check if position would be healthy after borrow
        if (getCollateralRatio(msg.sender) < LIQUIDATION_THRESHOLD) {
            revert InsufficientCollateral();
        }

        // mint syntetic assets
        _mint(msg.sender, amount);
        
        emit SynteticBorrowed(msg.sender, amount);
    }

    // repay syntetic assets
    function repaySyntetic(uint256 amount) public {
        balances[msg.sender].debt -= amount;
        _burn(msg.sender, amount);
        // send back the collateral
        // repay 1 coin = 270$
        // in eth, 270/3000 = 0.09 ether
        uint256 amountToWithdraw =(amount * (COIN_USDC_PRICE * 1e18 / ETH_USDC_PRICE))/ 1e18;
        withdrawCollateral(amountToWithdraw);
        emit SynteticRepaid(msg.sender, amount);
    }

    // Liquidate an unhealthy position
    function liquidate(address user, uint256 amountToRepay) public {
        // check if position is liquidatable
        if (!isLiquidatable(user)) revert PositionNotLiquidatable();

        // check if user has enough syntetic assets to repay
        if (balances[user].debt < amountToRepay) revert InsufficientSynteticAssets();

        // liquidator repays and burn the asset on behalf of the user
        balances[user].debt -= amountToRepay;
        _burn(user, amountToRepay);

        // liquidator receives 10% bonus of the amount repaid in collateral
        uint256 amountToWithDraw = (amountToRepay * (COIN_USDC_PRICE * 1e18 / ETH_USDC_PRICE))/ 1e18;
        uint256 reward = (amountToWithDraw * LIQUIDATION_BONUS) / 100;
                
        // update user's collateral
        // send the collateral back to the user

        balances[user].collateral = balances[user].collateral + amountToWithDraw - reward;
        
        // Transfer reward to liquidator
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Reward transfer failed");
        
        emit PositionLiquidated(user, msg.sender, reward);
    }

    function getCoinPrice() public view returns (int64) {
        bytes32 priceFeedId = 0xfee33f2a978bf32dd6b662b65ba8083c6773b494f8401194ec1870c640860245; // COIN/USD
        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceFeedId, 60);
        return price.price;
    }

    // gov can change the pyth address
    function setPythAddress(address newAddr) public onlyOwner {
        pythContract = newAddr;
    }

    // gov can change the prices
    function setEthPrice(uint256 newPrice) public onlyOwner {
        ETH_USDC_PRICE = newPrice;
    }

    function setCoinPrice(uint256 newPrice) public onlyOwner {
        COIN_USDC_PRICE = newPrice;
    }

}
