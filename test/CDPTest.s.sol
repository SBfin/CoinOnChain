// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {CDP} from "../src/CDP.sol";
import {console} from "forge-std/console.sol";

contract CDPTest is Test {
    CDP public cdp;
    uint256 public COLLATERAL = 1 ether;
    uint256 public INITIAL_BORROW = 0.2 ether;
    address public liquidator = address(0x1);


    function setUp() public {
        cdp = new CDP();

        // mint some ether for this asset
        vm.deal(address(this), 10000 ether);
        vm.deal(liquidator, 10000 ether);
    }

    modifier modDepositCollateral() {
        cdp.depositCollateral{value: COLLATERAL}(COLLATERAL);
        _;
    }

    function test_DepositCollateral() public {
        cdp.depositCollateral{value: COLLATERAL}(COLLATERAL);
        (uint256 collateral, uint256 debt) = cdp.balances(address(this));
        assertEq(collateral, COLLATERAL);
        assertEq(debt, 0);
    }
    
    function test_WithdrawCollateralAfterDepositNoDebt() public modDepositCollateral payable {
        uint256 balanceBefore = address(this).balance;
        cdp.withdrawCollateral(1 ether);
        (uint256 collateral, uint256 debt) = cdp.balances(address(this));
        assertEq(collateral, 0);
        assertEq(debt, 0);
        assertEq(address(this).balance, balanceBefore + 1 ether);
    }

    function test_BorrowSyntetic() public modDepositCollateral payable {
        cdp.borrowSyntetic(INITIAL_BORROW);
        (uint256 collateral, uint256 debt) = cdp.balances(address(this));
        assertEq(collateral, COLLATERAL);
        assertEq(debt, INITIAL_BORROW);
        assertEq(cdp.balanceOf(address(this)), INITIAL_BORROW);
    }

    function test_BorrowSynteticInsufficientCollateral() public modDepositCollateral payable {
        uint256 amount = COLLATERAL*cdp.ETH_USDC_PRICE()*120/(cdp.COIN_USDC_PRICE()*150);
        console.log("amount", amount);
        vm.expectRevert(CDP.InsufficientCollateral.selector);
        cdp.borrowSyntetic(amount);
    }

    function test_RepaySyntetic() public modDepositCollateral payable {
        cdp.borrowSyntetic(INITIAL_BORROW);
        cdp.repaySyntetic(INITIAL_BORROW);
        (uint256 collateral, uint256 debt) = cdp.balances(address(this));
        assertEq(collateral, COLLATERAL);
        assertEq(debt, 0);
        assertEq(cdp.balanceOf(address(this)), 0);
    }

    // price change and position becomes unhealthy
    function test_LiquidationAfterPriceChange() public modDepositCollateral payable {
        cdp.borrowSyntetic(INITIAL_BORROW);
        uint256 price = COLLATERAL*cdp.ETH_USDC_PRICE()*120/(INITIAL_BORROW*150);
        console.log("price", price);
        //check health factor
        assertLt(cdp.getCollateralRatio(address(this)), cdp.LIQUIDATION_THRESHOLD());
        // liquidate
        vm.prank(liquidator);
        cdp.liquidate(address(this), INITIAL_BORROW*50/100);
    }

    receive() external payable {}

}
