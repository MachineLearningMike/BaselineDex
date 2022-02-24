import { expect } from "chai";
import hre, { deployments, waffle } from "hardhat";
import "@nomiclabs/hardhat-ethers";

import { CrossFactory } from "../types/CrossFactory";
import { CrossRouter } from "../types/CrossRouter";
import { CrssToken } from "../types/CrssToken";
import { XCrssToken } from "../types/XCrssToken";
import { CrossFarm } from "../types/CrossFarm";
import { WBNB as WBNBT } from "../types/WBNB";

describe("deployment test", async () => {
  const [owner, userA, userB] = waffle.provider.getWallets();

  const setupTest = deployments.createFixture(async ({ deployments }) => {
    await deployments.fixture();

    const Factory = await hre.ethers.getContractFactory("CrossFactory");
    const factory = (await Factory.deploy(owner.address)) as CrossFactory;
    await factory.deployed();

    const WBNB = await hre.ethers.getContractFactory("WBNB");
    const wbnb = (await WBNB.deploy()) as WBNBT;
    await wbnb.deployed();

    const Router = await hre.ethers.getContractFactory("CrossRouter");
    const router = (await Router.deploy(factory.address, wbnb.address)) as CrossRouter;
    await router.deployed();

    // @notice, require to add in deploy script too
    await factory.setRouter(router.address);

    const Crss = await hre.ethers.getContractFactory("CrssToken");
    const crss = (await hre.upgrades.deployProxy(Crss, [router.address])) as CrssToken;
    await crss.deployed();

    await router.setCrssContract(crss.address);

    const crssPerBlock = 100;
    const startBlock = 123456;
    const Farm = await hre.ethers.getContractFactory("CrossFarm");
    const farm = (await hre.upgrades.deployProxy(Farm, [
      crss.address,
      userA.address,
      router.address,
      crssPerBlock,
      startBlock,
    ])) as CrossFarm;
    await farm.deployed();

    const XCrss = await hre.ethers.getContractFactory("xCrssToken");
    const xCrss = (await hre.upgrades.deployProxy(XCrss, [crss.address])) as XCrssToken;
    await xCrss.deployed();

    await farm.setXCrss(xCrss.address);
    await crss.setFarm(farm.address);
    await xCrss.setFarm(farm.address);

    crss.connect(owner).mint(userA.address, "100000000");

    return {
      factory,
      router,
      crss,
      xCrss,
      farm,
    };
  });

  let factory: CrossFactory, router: CrossRouter, crss: CrssToken, xCrss: XCrssToken, farm: CrossFarm;

  before("load fixture loader", async () => {
    ({ factory, router, crss, xCrss, farm } = await setupTest());
  });

  describe("factory test", async () => {
    it("factory should have router address", async () => {
      const router2 = await factory.router();
      expect(router2).to.be.equal(router.address);
    });

    it("feeToSetter should be same with adminSigner", async () => {
      const feeToSetter = await factory.feeToSetter();
      expect(feeToSetter).to.be.equal(owner.address);
    });

    it("setRouter should only be callable by adminSigner", async () => {
      await factory.connect(owner).setRouter(router.address);

      await expect(factory.connect(userA).setRouter(router.address)).to.be.revertedWith("Cross: FORBIDDEN");

      await factory.createPair(crss.address, xCrss.address);
      await factory.connect(owner).setRouter(router.address);
    });
  });

  describe("router test", async () => {
    it("router should have factory address", async () => {
      const factory2 = await router.factory();
      expect(factory2).to.be.equal(factory.address);
    });

    it("the owner of router should be same with feeToSetter of factory", async () => {
      const routerOwner = await router.owner();
      const feeToSetter = await factory.feeToSetter();

      expect(routerOwner).to.be.equal(feeToSetter);
      expect(routerOwner).to.be.equal(owner.address);
    });

    it("setCrssContract should only be callable by adminSigner", async () => {
      await router.connect(owner).setCrssContract(crss.address);
      // expect("setCrssContract").to.be.calledOnContract(factory);

      await expect(router.connect(userA).setCrssContract(crss.address)).to.be.revertedWith("Cross: FORBIDDEN");
    });
  });

  describe("crss test", async () => {
    it("crss should have router address", async () => {
      const router2 = await crss.router();
      expect(router2).to.be.equal(router.address);
    });

    it("the owner of crss should be same with the owner of router", async () => {
      const routerOwner = await router.owner();
      const crssOwner = await crss.owner();
      expect(routerOwner).to.be.equal(crssOwner);
      expect(crssOwner).to.be.equal(owner.address);
    });

    it("setRouter should only be callable by adminSigner", async () => {
      await crss.connect(owner).setRouter(router.address);
      // expect("setRouter").to.be.calledOnContract(crss);

      await expect(crss.connect(userA).setRouter(router.address)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("mint should be callable by farm", async () => {
      await farm.connect(owner).add("2000", crss.address, true);
      await crss.connect(userA).approve(farm.address, "2000");
      await farm.connect(userA).enterStaking("2000");
    });
  });

  describe("xcrss test", async () => {
    it("xcrss should have farm address", async () => {
      const farm2 = await xCrss.crssFarm();
      expect(farm2).to.be.equal(farm.address);
    });

    it("the owner of xcrss should be same with the owner of crss", async () => {
      const xcrssOwner = await xCrss.owner();
      const crssOwner = await crss.owner();

      expect(xcrssOwner).to.be.equal(crssOwner);
      expect(xcrssOwner).to.be.equal(owner.address);
    });

    it("mint should be callable by farm", async () => {
      await farm.connect(owner).add("2000", crss.address, true);
      await crss.connect(userA).approve(farm.address, "2000");
      await farm.connect(userA).enterStaking("2000");
    });
  });

  describe("farm test", async () => {
    it("farm should have router address", async () => {
      const router2 = await farm.router();
      expect(router2).to.be.equal(router.address);
    });

    it("farm should have crss/xcrss address", async () => {
      const crss2 = await farm.crss();
      expect(crss2).to.be.equal(crss.address);
      const xcrss2 = await farm.xcrss();
      expect(xcrss2).to.be.equal(xCrss.address);
    });

    it("the owner of farm should be same with the owner of crss", async () => {
      const farmOwner = await farm.owner();
      const crssOwner = await crss.owner();

      expect(farmOwner).to.be.equal(crssOwner);
      expect(farmOwner).to.be.equal(owner.address);
    });
  });
});
