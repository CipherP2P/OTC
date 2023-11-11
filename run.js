
const Utils = require('./common');
let data = require("./contract.json")
let utils = new Utils()

let network;
if("network" in process.env) {
    network = process.env.network
}else {
    network = process.argv[2]
}

if(!network) {
    console.error("无效参数")
    return
}


if(!(network in data)) {
    data[network] = {}
}

let deployItem = async (dir,verify = false) => {
    let result;
    let json;
    result = await utils.runCommand(`cd ${dir} && npx hardhat run --network ${network} scripts/deploy.ts`)
    json = await utils.getFileContent(`./${dir}/contract.json`,true)
    data[network] = { ...data[network], ...json }
    console.log(result)
    try{
        result = verify && await utils.runCommand(`cd ${dir} && npx hardhat run --network ${network} scripts/verify.ts`)
        verify && console.log(result)
    }catch(err){ console.log(err) }
    return data
}

let run = async () => {
    await deployItem("OTC",true)


    await utils.replaceContent('./contract.json',JSON.stringify(data,null,4))
    console.log(data)
}



run()