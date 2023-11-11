import { HardhatUserConfig } from "hardhat/config";
import type { NetworkUserConfig } from "hardhat/types";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const bscTestnet: NetworkUserConfig = {
	url: "https://bsc-testnet.publicnode.com",
	chainId: 97,
	accounts: [process.env.KEY_TESTNET!],
};


const localhost: NetworkUserConfig = {
	url: "http://192.168.1.175:7545",
	chainId: 1337,
	accounts: [process.env.KEY_TESTNET!],
};

const config: HardhatUserConfig = {
	networks: {
		hardhat: {
		},
		// bscTestnet
		bscTestnet,
		localhost
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_API_KEY,
	},
	solidity: {
		compilers: [
			{
				version: "0.8.14",
				settings: {
					optimizer: {
						enabled: true,
						runs: 5000

					}
				}
			}
		]
	}
};

export default config;
