import "@nomiclabs/hardhat-waffle";
import "@openzeppelin/hardhat-upgrades";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";

import { resolve } from "path";

import { config as dotenvConfig } from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import { NetworkUserConfig } from "hardhat/types";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const privateKey: string | undefined = process.env.PRIVATE_KEY ?? "NO_PRIVATE_KEY";
const alchemyApiKey: string | undefined = process.env.ALCHEMY_API_KEY ?? "NO_ALCHEMY_API_KEY";

const config: HardhatUserConfig = {
    defaultNetwork: "hardhat",
    gasReporter: {
        currency: "USD",
        enabled: process.env.REPORT_GAS ? true : false,
        excludeContracts: [],
        src: "./contracts",
    },
    networks: {
        hardhat: {
            gasPrice: "auto",
            gasMultiplier: 2,
        },
        localnet: {
            // Ganache etc.
            url: "http://127.0.0.1:8545",
            gasPrice: "auto",
            gasMultiplier: 2,
        },
        mainnet: {
            url: `https://bsc-dataseed.binance.org/`,
            accounts: [`0x${privateKey}`],
        },
        testnet: {
            url: `https://data-seed-prebsc-1-s1.binance.org:8545`,
            accounts: [`0x${privateKey}`],
        },
    },
    paths: {
        artifacts: "./artifacts",
        cache: "./cache",
        sources: "./contracts",
        tests: "./test",
        deploy: "./scripts/deploy",
        deployments: "./deployments",
    },
    solidity: {
        compilers: [
            {
                version: "0.8.3",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
        settings: {
            outputSelection: {
                "*": {
                    "*": ["storageLayout"],
                },
            },
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        }
    },
    typechain: {
        outDir: "types",
        target: "ethers-v5",
    },
    etherscan: {
        apiKey: process.env.BSC_API_KEY,
    },
};

export default config;
