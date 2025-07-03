// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/ShonaProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ShonaProxyBaseScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // For Base network deployment
        // Using nga token as the main ATLAS token for stable functionality
        IERC20 ngaToken = IERC20(0x0b9F23645C9053BecD257f2De5FD961091112fb1); // nga stable token address
        
        console.log("Deploying ShonaProxy on Base network...");
        console.log("nga token (ATLAS):", address(ngaToken));
        console.log("USDC token:", 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        console.log("IDRX token:", 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22);
        
        ShonaProxy proxy = new ShonaProxy(ngaToken);
        console.log("ShonaProxy deployed at:", address(proxy));
        
        // Set the fee rate to 0.1% (10 basis points)
        proxy.setStableFeeRate();
        console.log("Fee rate set to 0.1% for stable tokens");
        
        // Verify stable token configuration
        console.log("nga is stable token:", proxy.isStableToken(address(ngaToken)));
        console.log("USDC is stable token:", proxy.isStableToken(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
        console.log("IDRX is stable token:", proxy.isStableToken(0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22));
        
        console.log("Current fee rate:", proxy.getFeeRate(), "basis points (0.1%)");

        vm.stopBroadcast();
    }
}