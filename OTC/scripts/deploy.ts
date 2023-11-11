import { ethers } from "hardhat";
import { writeFileSync } from "fs";
async function main() {

	const margin = await ethers.deployContract("Margin", []);

	await margin.waitForDeployment();

	const lock = await ethers.deployContract("OTC", [
		margin.target,
		"0x55959f0D5e1b7DC57fe4079e596b8BBafFF123B1",
		"0xdb4ceC070c6aCfaF012CaEe845910a53E78E6a81"
	]);

	await lock.waitForDeployment();
	writeFileSync(
		`./contract.json`,
		JSON.stringify(
			{
				OTC: lock.target,
				Margin: margin.target
			},
			null,
			2
		)
	);
	console.log(`
	Deployed: 
		Margin:${lock.target}
		OTC:${lock.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
