// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/ShonaProxy.sol";

contract ShonaProxyScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ShonaProxy proxy = new ShonaProxy();
        console.log("ShonaProxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
