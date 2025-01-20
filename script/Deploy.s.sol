// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CDP} from "../src/CDP.sol";

contract Deploy {
    function run() public {
        new CDP();
    }
}
