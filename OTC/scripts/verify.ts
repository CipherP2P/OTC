import { verifyContract, sleep } from "./verify-tools";
import json from "../contract.json"

async function main() {

  // Verify masterChefV3
  console.log("Verify Contract");
  await verifyContract(json.Margin, []);
  await sleep(10000);
  await verifyContract(json.OTC, [
    json.Margin,
		"0x55959f0D5e1b7DC57fe4079e596b8BBafFF123B1",
		"0xdb4ceC070c6aCfaF012CaEe845910a53E78E6a81"
  ]);
  await sleep(10000);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
