// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/ShonaProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ShonaProxyScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Use the actual ATLAS token address for deployment
        IERC20 atlas = IERC20(0x0b9F23645C9053BecD257f2De5FD961091112fb1);
        ShonaProxy proxy = new ShonaProxy(atlas);
        console.log("ShonaProxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
