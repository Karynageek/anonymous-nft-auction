import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
dotenv.config();

const defaultMnemonic = "test test test test test test test test test test test junk";
const defaultRpc = "http://127.0.0.1"

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 1000000,
      },
    },
  },
  networks: {
    cypher: {
      url: process.env.CYPHER_RPC || defaultRpc,
      accounts: { mnemonic: process.env.MNEMONIC || defaultMnemonic },
      chainId: 9000,
      timeout: 200000,  // Increase the timeout to 200 seconds (default is 20 seconds)
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
  },
};

export default config;
