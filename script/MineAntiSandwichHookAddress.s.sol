// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import {HookMiner} from "../src/utils/HookMiner.sol";
import {AntiSandwichHookImplementation} from "../src/general/AntiSandwichHookImplementation.sol";

contract AntiSandwichHookAddressMiner is Script {
    address constant POOL_MANAGER_ADDRESS = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    function run() external {
        address SUPER_HOOK = vm.envAddress("SUPER_HOOK");
        bytes memory initCode = abi.encodePacked(
            type(AntiSandwichHookImplementation).creationCode,
            abi.encode(SUPER_HOOK, POOL_MANAGER_ADDRESS)
        );

        uint160 mask = HookMiner.permissionsToMask(
            false, // beforeInitialize
            false, // afterInitialize
            false, // beforeAddLiquidity
            false, // afterAddLiquidity
            false, // beforeRemoveLiquidity
            false, // afterRemoveLiquidity
            true,  // beforeSwap
            true,  // afterSwap
            false, // beforeDonate
            false, // afterDonate
            false, // beforeSwapReturnDelta
            true,  // afterSwapReturnDelta
            false, // afterAddLiquidityReturnDelta
            false  // afterRemoveLiquidityReturnDelta
        );

        uint256 salt = HookMiner.findSaltForMask(CREATE2_FACTORY, initCode, mask);
        console.log("ANTI_SANDWICH_SALT:", salt);

        address predicted = HookMiner.computeCreate2Address(
            salt,
            keccak256(initCode),
            CREATE2_FACTORY
        );
        
        console.log("ANTI_SANDWICH_SALT:", salt);
        console.log("Predicted:   ", predicted);
        console.log("Mask bits:   ", uint160(predicted) & HookMiner.ALL_HOOK_MASK);
    }
}