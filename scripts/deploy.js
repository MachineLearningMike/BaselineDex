async function main() {
  const { ethers, upgrades } = require("hardhat");

  const [deployer, alice, bob, carol] = await ethers.getSigners();

  /***********************

    *      DEPLOY START

    ************************/

  const Factory = await ethers.getContractFactory("CrossFactory");
  const factory = await Factory.deploy(deployer.address);

  console.log("\nFactory Deployed: ", factory.address);

  const Router = await ethers.getContractFactory("CrossRouter");
  const router = await Router.deploy(factory.address, carol.address);

  console.log("\nRouter Deployed: ", router.address);

  factory.setRouter(router.address);
  console.log("\nFactory Router Set: ", router.address);

  const Crss = await ethers.getContractFactory("CrssToken");
  const crss = await upgrades.deployProxy(Crss, [router.address]);

  console.log("\nCrssToken Deployed: ", crss.address);

  router.setCrssContract(crss.address);
  console.log("\nCRSS token is set on Router:", crss.address);

  const crssPerBlock = 100;
  const startBlock = 123456;
  const CrossFarm = await ethers.getContractFactory("CrossFarm");
  const farm = await upgrades.deployProxy(CrossFarm, [
    crss.address,
    alice.address,
    router.address,
    crssPerBlock,
    startBlock,
  ]);

  console.log("\nFarm deployed: ", farm.address);

    await crss.setFarm(farm.address);
    console.log("\nFarm is set on CRSS: ", farm.address)

    const xCrss = await ethers.getContractFactory("xCrssToken")
    const xcrss = await upgrades.deployProxy(xCrss, [router.address])

  console.log("\nXCrssToken deployed: ", xcrss.address);

    await xcrss.setFarm(farm.address);
    console.log("\nFarm is set on XCRSS: ", farm.address)

    await farm.setXCrss(xcrss.address);
    console.log("\nXCRSS token is set on Farm: ", xcrss.address)

  /***********************

    *      UPGRADE START

    ************************/

  const Crss2 = await ethers.getContractFactory("CrssToken2");
  const crss2 = await upgrades.upgradeProxy(crss.address, Crss2);

  console.log("\nCrssToken Upgraded: ", await crss2.getVersion());

  const xCrss2 = await ethers.getContractFactory("xCrssToken2");
  const xcrss2 = await upgrades.upgradeProxy(xcrss.address, xCrss2);

  console.log("\nxCrssToken Upgraded: ", await xcrss2.getVersion());

  const Farm2 = await ethers.getContractFactory("CrossFarm2");
  const farm2 = await upgrades.upgradeProxy(farm.address, Farm2);

  console.log("\nxCrssToken Upgraded: ", await xcrss2.getVersion());
}

main((err) => {
  if (err) {
    console.log(err);
  }
});
