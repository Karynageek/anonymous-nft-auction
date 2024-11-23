import hre, { ethers } from "hardhat";
import { EncryptedERC20, EncryptedERC20__factory } from "../typechain-types";

async function main() {
    let token: EncryptedERC20;
    const name = "EncryptedERC20";
    const symbol = "EER20";

    const EncryptedERC20 = (await ethers.getContractFactory('EncryptedERC20')) as EncryptedERC20__factory;

    token = await EncryptedERC20.deploy(name, symbol);

    await token.waitForDeployment();

    console.log("EncryptedERC20 deployed to:", token.target);

    await token.deploymentTransaction()?.wait(5)

    await hre.run("verify:verify", {
        address: token.target,
        constructorArguments: [name, symbol],
    });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
