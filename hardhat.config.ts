import { HardhatUserConfig } from 'hardhat/types';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
import '@openzeppelin/hardhat-upgrades';
import 'hardhat-typechain';
import 'hardhat-deploy';
import 'solidity-coverage';
import 'hardhat-gas-reporter';
import { config as dotEnvConfig } from 'dotenv';

dotEnvConfig();

const INFURA_API_KEY = process.env.INFURA_API_KEY || '';
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const GOERLI_PRIVATE_KEY =
	process.env.GOERLI_PRIVATE_KEY || '0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3'; // well known private key
const MAINNET_PRIVATE_KEY =
	process.env.MAINNET_PRIVATE_KEY || '0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3'; // well known private key

const config: HardhatUserConfig = {
	defaultNetwork: 'hardhat',
	solidity: {
		compilers: [
			{
				version: '0.8.9',
				settings: {
					optimizer: {
						enabled: true,
						runs: 10000,
					},
				},
			},
		],
	},
	mocha: {
		timeout: 180_000,
	},
	networks: {
		hardhat: {
			accounts: {
				count: 128,
			},
		},
		localhost: {
			url: 'http://127.0.0.1:8545/',
		},
		goerli: {
			url: `https://goerli.infura.io/v3/${INFURA_API_KEY}`,
			accounts: [GOERLI_PRIVATE_KEY],
		},
		mainnet: {
			url: `https://mainnet.infura.io/v3/${INFURA_API_KEY}`,
			accounts: [MAINNET_PRIVATE_KEY],
		},
	},
	etherscan: {
		apiKey: ETHERSCAN_API_KEY,
	},
};

if (process.env.CONTRACTS_TARGET_NETWORK && process.env.CONTRACTS_DEPLOYER_KEY && process.env.CONTRACTS_RPC_URL) {
	config.networks = config.networks || {};
	config.networks[process.env.CONTRACTS_TARGET_NETWORK] = {
		accounts: [process.env.CONTRACTS_DEPLOYER_KEY],
		url: process.env.CONTRACTS_RPC_URL,
		live: true,
		saveDeployments: true,
		tags: [process.env.CONTRACTS_TARGET_NETWORK],
	};
}

export default config;
