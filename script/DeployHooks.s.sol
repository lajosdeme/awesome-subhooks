// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {AwesomeHooksFactory} from "src/general/AwesomeHooksFactory.sol";
import {WhitelistHookFactory} from "src/factories/WhitelistHookFactory.sol";
import {KYCHookFactory} from "src/factories/KYCHookFactory.sol";
import {MultiSigSwapHookFactory} from "src/factories/MultiSigSwapHookFactory.sol";
import {VotingEscrowHookFactory} from "src/factories/VotingEscrowHookFactory.sol";
import {RehypothecationERC4626HookFactory} from "src/factories/RehypothecationERC4626HookFactory.sol";
import {ERC721HookFactory} from "src/factories/ERC721HookFactory.sol";

import {AntiSandwichHookImplementation} from "src/general/AntiSandwichHookImplementation.sol";
import {LiquidityPenaltyHookImplementation} from "src/general/LiquidityPenaltyHookImplementation.sol";
import {LimitOrderHookImplementation} from "src/general/LimitOrderHookImplementation.sol";
import {FullRange} from "src/v4-periphery-examples/FullRange.sol";
import {GeomeanOracle} from "src/v4-periphery-examples/GeomeanOracle.sol";
import {VolatilityOracle} from "src/v4-periphery-examples/VolatilityOracle.sol";
import {OracleHookWithV3AdaptersImplementation} from "src/oracles/panoptic/OracleHookWithV3AdaptersImplementation.sol";

contract DeployHooks is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("KEY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address superHook = vm.envAddress("SUPER_HOOK");

        vm.startBroadcast(deployerPrivateKey);

        deploySubFactories(superHook, poolManager);
        deployHooks(superHook, poolManager);

        vm.stopBroadcast();
    }

    function deploySubFactories(address superHook, address poolManager) internal {
        IPoolManager pm = IPoolManager(poolManager);

        address[] memory factories = new address[](6);

        address whitelistFactory = address(new WhitelistHookFactory(superHook, pm));
        console.log("WhitelistHookFactory deployed at:", whitelistFactory);
        factories[0] = whitelistFactory;

        address kycFactory = address(new KYCHookFactory(superHook, pm));
        console.log("KYCHookFactory deployed at:", kycFactory);
        factories[1] = kycFactory;

        address multiSigFactory = address(new MultiSigSwapHookFactory(superHook, pm));
        console.log("MultiSigSwapHookFactory deployed at:", multiSigFactory);
        factories[2] = multiSigFactory;

        address votingEscrowFactory = address(new VotingEscrowHookFactory(superHook, pm));
        console.log("VotingEscrowHookFactory deployed at:", votingEscrowFactory);
        factories[3] = votingEscrowFactory;

        address rehypothecationFactory = address(new RehypothecationERC4626HookFactory(superHook, pm));
        console.log("RehypothecationERC4626HookFactory deployed at:", rehypothecationFactory);
        factories[4] = rehypothecationFactory;

        address erc721Factory = address(new ERC721HookFactory(superHook, pm));
        console.log("ERC721HookFactory deployed at:", erc721Factory);
        factories[5] = erc721Factory;

        AwesomeHooksFactory factory = new AwesomeHooksFactory(superHook, pm, factories);
        console.log("AwesomeHooksFactory deployed at:", address(factory));

    }

    function deployHooks(address superHook, address poolManager) internal {
        IPoolManager pm = IPoolManager(poolManager);

        deployAntiSandwichHook(superHook, pm);
        deployLiquidityPenaltyHook(superHook, pm);
        deployLimitOrderHook(superHook, pm);
        deployFullRange(superHook, pm);
        deployGeomeanOracle(pm, superHook);
        deployVolatilityOracle(superHook, pm);
        
        deployOracleHookV3Adapters(superHook, pm);
    }

    function deployAntiSandwichHook(address superHook, IPoolManager pm) internal {
        uint256 salt = vm.envUint("ANTI_SANDWICH_SALT");
        bytes32 saltBytes = bytes32(salt);
        address hook = address(new AntiSandwichHookImplementation{salt: saltBytes}(superHook, pm));
        console.log("AntiSandwichHookImplementation deployed at:", hook);
    }

    function deployLiquidityPenaltyHook(address superHook, IPoolManager pm) internal {
        uint256 salt = vm.envUint("LIQUIDITY_PENALTY_SALT");
        bytes32 saltBytes = bytes32(salt);
        address hook = address(new LiquidityPenaltyHookImplementation{salt: saltBytes}(superHook, pm, 1));
        console.log("LiquidityPenaltyHookImplementation deployed at:", hook);
    }

    function deployLimitOrderHook(address superHook, IPoolManager pm) internal {
        uint256 salt = vm.envUint("LIMIT_ORDER_SALT");
        bytes32 saltBytes = bytes32(salt);
        address hook = address(new LimitOrderHookImplementation{salt: saltBytes}(superHook, pm));
        console.log("LimitOrderHookImplementation deployed at:", hook);
    }

    function deployFullRange(address superHook, IPoolManager pm) internal {
        uint256 salt = vm.envUint("FULL_RANGE_SALT");
        bytes32 saltBytes = bytes32(salt);
        address hook = address(new FullRange{salt: saltBytes}(superHook, pm));
        console.log("FullRange deployed at:", hook);
    }

    function deployGeomeanOracle(IPoolManager pm, address superHook) internal {
        uint256 salt = vm.envUint("GEOMEAN_SALT");
        bytes32 saltBytes = bytes32(salt);
        address hook = address(new GeomeanOracle{salt: saltBytes}(pm, superHook));
        console.log("GeomeanOracle deployed at:", hook);
    }

    function deployVolatilityOracle(address superHook, IPoolManager pm) internal {
        uint256 salt = vm.envUint("VOLATILITY_ORACLE_SALT");
        bytes32 saltBytes = bytes32(salt);
        address hook = address(new VolatilityOracle{salt: saltBytes}(superHook, pm));
        console.log("VolatilityOracle deployed at:", hook);
    }

    function deployOracleHookV3Adapters(address superHook, IPoolManager pm) internal {
        uint256 salt = vm.envUint("ORACLE_HOOK_V3_ADAPTERS_SALT");
        bytes32 saltBytes = bytes32(salt);
        address hook = address(new OracleHookWithV3AdaptersImplementation{salt: saltBytes}(superHook, pm, 200));
        console.log("OracleHookWithV3AdaptersImplementation deployed at:", hook);
    }
}

/* 
  WhitelistHookFactory deployed at: 0x3902C89EB479911b62c0C302b5A243c72A74f903
  KYCHookFactory deployed at: 0x7b44e62Df0cFFA3bD7798735fc338c1BE845Db26
  MultiSigSwapHookFactory deployed at: 0xee21335feC8503da8524B4Db674D4aE150C59FF8
  VotingEscrowHookFactory deployed at: 0x724C534F04eC39dE159560B6763F156A2ce69b35
  RehypothecationERC4626HookFactory deployed at: 0xf773fe4Fc536512e365b4425709fBF966E9DAFa4
  ERC721HookFactory deployed at: 0x413E09d92BDA6Bb08786E58E58BB48197aAE64FF
  AwesomeHooksFactory deployed at: 0xc5dfAA902534Db047aE06782e0C8cDc47a286091
  AntiSandwichHookImplementation deployed at: 0xC82F0f7e159B1E4519bDA116c513b0cfdee0C0c4
  LiquidityPenaltyHookImplementation deployed at: 0x65C44628493d52085CaA3Bff66d4B494F1B04503
  LimitOrderHookImplementation deployed at: 0x4aEad51cdAC125EBA30226E2C57CA7eC2e2bD040
  FullRange deployed at: 0xEDDFA67f1CC409343409B657711Bbdc212392880
  GeomeanOracle deployed at: 0xCa591d04059E529f94D9cd0F6eb7af685CAc3a80
  VolatilityOracle deployed at: 0x4A4e16539b4F62e1E398c2CcBDb252CD91FBf000
  OracleHookWithV3AdaptersImplementation deployed at: 0x3511E489D7fd9216F4D52a0e18bd21E954E01080
 */