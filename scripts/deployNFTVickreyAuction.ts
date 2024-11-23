import hre, { ethers } from "hardhat";
import { NFTVickreyAuction, NFTVickreyAuction__factory } from "../typechain-types";

async function main() {
    let auction: NFTVickreyAuction;

    const NFTVickreyAuction = (await ethers.getContractFactory('NFTVickreyAuction')) as NFTVickreyAuction__factory;
    auction = await NFTVickreyAuction.deploy();

    await auction.waitForDeployment();

    console.log("Auction deployed to:", auction.target);

    await auction.deploymentTransaction()?.wait(5)

    await hre.run("verify:verify", {
        address: auction.target,
        constructorArguments: [],
    });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
