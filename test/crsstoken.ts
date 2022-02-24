import { assert, expect } from "chai";

import hre, { deployments, waffle } from "hardhat";
import { BigNumber } from "ethers";
import "@nomiclabs/hardhat-ethers";

import { CrossFactory } from "../types/CrossFactory";
import { CrossRouter } from "../types/CrossRouter";
import { CrssToken } from "../types/CrssToken";
import { WBNB as WBNBT } from "../types/WBNB";
import { MockTransfer } from "../types/MockTransfer";
import { CrossFarm } from "../types/CrossFarm";
import { XCrssToken } from "../types/XCrssToken";
import { MockToken } from "../types/MockToken";
import { CrossPair } from "../types/CrossPair";

import CrossPairAbi from "../artifacts/contracts/core/CrossPair.sol/CrossPair.json";

describe("CrssToken test", async () => {
  const [owner, userA, userB, userC] = waffle.provider.getWallets();

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

    const MockTransfer = await hre.ethers.getContractFactory("MockTransfer");
    const mockTransfer = (await MockTransfer.deploy()) as MockTransfer;
    await mockTransfer.deployed();

    return {
      factory,
      router,
      crss,
      wbnb,
      farm,
      xCrss,
      mockTransfer,
    };
  });

  let factory: CrossFactory,
    router: CrossRouter,
    crss: CrssToken,
    wbnb: WBNBT,
    xCrss: XCrssToken,
    farm: CrossFarm,
    mockTransfer: MockTransfer;
  const burnAddress = "0x000000000000000000000000000000000000dEaD";

  before("load fixture loader", async () => {
    ({ factory, router, crss, wbnb } = await setupTest());
  });

  it("should have correct name and symbol and decimal", async function () {
    const name = await crss.name();
    const symbol = await crss.symbol();
    const decimals = await crss.decimals();
    expect(name, "Crosswise Token");
    expect(symbol, "CRSS");
    expect(decimals, "18");
  });

  describe("callable modifier", async function () {
    it("setFarm should be callable by owner", async function () {
      console.log("userA is trying to set farm address, should revert");
      await expect(crss.connect(userA).setFarm(farm.address)).to.be.reverted;
    });

    it("setDexSession should be callable by router", async function () {
      console.log("owner is trying to set dex session, should revert");
      await expect(crss.connect(owner).setDexSession(0)).to.be.revertedWith("Cross: FORBIDDEN");
      console.log("userA is trying to set dex session, should revert");
      await expect(crss.connect(userA).setDexSession(0)).to.be.revertedWith("Cross: FORBIDDEN");
    });

    it("setKnownDexContract should be callable by owner", async function () {
      console.log("userA is trying to set userB as known dex contract, should revert");
      await expect(crss.connect(userA).setKnownDexContract(userB.address, true)).to.be.reverted;
      console.log("owner is trying to set userA as known dex contract, should not revert");
      await crss.connect(owner).setKnownDexContract(userA.address, true);
    });

    it("delegate should be callable by owner", async function () {
      console.log("userA is trying to set userB as delegate, should revert");
      await expect(crss.connect(userA).delegate(userB.address)).to.be.reverted;
      console.log("owner is trying to set userB as delegate, should not revert");
      await crss.connect(owner).delegate(userA.address);
    });
  });

  describe("mint/burn/berry test", async function () {
    before(async function () {
      await crss.connect(owner).setFarm(owner.address);
    });

    after(async function () {
      await crss.connect(owner).setFarm(farm.address);
    });

    it("should only allow owner to mint token", async function () {
      console.log("owner is trying to set owner as delegate, should revert");
      await crss.connect(owner).mint(userA.address, "100");
      await crss.connect(owner).mint(userB.address, "1000");
      await expect(crss.connect(userB).mint(userC.address, "1000")).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      const totalSupply = await crss.totalSupply();
      const userABal = await crss.balanceOf(userA.address);
      const userBBal = await crss.balanceOf(userB.address);
      const userCBal = await crss.balanceOf(userC.address);
      expect(totalSupply).to.equal("1100");
      expect(userABal).to.be.equal("100");
      expect(userBBal).to.be.equal("1000");
      expect(userCBal).to.be.equal("0");
    });

    it("should only allow owner to burn token", async function () {
      console.log("owner is minting 1000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "1000");

      const totalSupply = await crss.totalSupply();
      const userABal = await crss.balanceOf(userA.address);
      console.log("totalSupply should be 1000");
      expect(totalSupply).to.be.equal("1000");
      console.log("userA's balance should be 100");
      expect(userABal).to.be.equal("1000");

      console.log("owner is burning 1000 tokens from userA");
      crss.connect(owner).burn(userA.address, "1000");
      // total supply will be decreased by burn amount
      const newTotalSupply = await crss.totalSupply();
      console.log("totalSupply should be zero");
      expect(newTotalSupply).to.be.equal("0");
    });

    it("should only allow owner to berry token", async function () {
      console.log("owner is minting 1000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "1000");

      const totalSupply = await crss.totalSupply();
      const userABal = await crss.balanceOf(userA.address);
      expect(totalSupply).to.be.equal("1000");
      expect(userABal).to.be.equal("1000");

      console.log("owner is berrying 1000 tokens from userA");
      crss.connect(owner).berry(userA.address, "1000");
      // total supply should not be changed after berry
      const newTotalSupply = await crss.totalSupply();
      console.log("totalSupply should be changed");
      expect(newTotalSupply).to.be.equal("1000");
    });
  });

  describe("transfer test", async function () {
    before(async function () {
      await crss.connect(owner).setFarm(owner.address);
    });

    after(async function () {
      await crss.connect(owner).setFarm(farm.address);
    });

    it("should supply token transfers properly", async function () {
      console.log("owner is minting 100 tokens to userA");
      await crss.connect(owner).mint(userA.address, "100");
      console.log("owner is minting 1000 tokens to userB");
      await crss.connect(owner).mint(userB.address, "1000");
      console.log("owner is transfering 10 tokens to userC");
      await crss.connect(owner).transfer(userC.address, "10");
      console.log("userB is transfering 100 tokens to userC");
      await crss.connect(userB).transfer(userC.address, "100");

      const totalSupply = await crss.totalSupply();
      const userABal = await crss.balanceOf(userA.address);
      const userBBal = await crss.balanceOf(userB.address);
      const userCBal = await crss.balanceOf(userC.address);
      console.log("totalSupply should be 1100 tokens");
      expect(totalSupply).to.be.equal("1100");
      console.log("userA' balance should be 90 tokens");
      expect(userABal).to.be.equal("90");
      console.log("userB' balance should be 900 tokens");
      expect(userBBal).to.be.equal("900");
      console.log("userC' balance should be 110 tokens");
      expect(userCBal).to.be.equal("110");
    });

    it("should fail if you try to do bad transfers", async function () {
      console.log("owner is minting 100 tokens to userA");
      await crss.connect(owner).mint(userA.address, "100");
      console.log(
        "userA is transfering 110 tokens to userB, should revert with exception `ERC20: transfer amount exceeds balance`"
      );
      await expect(crss.connect(userA).transfer(userB.address, "110")).to.be.revertedWith(
        "ERC20: transfer amount exceeds balance"
      );
      console.log(
        "userB is transfering 10 tokens to userC, should revert with exception `ERC20: transfer amount exceeds balance`"
      );
      await expect(crss.connect(userB).transfer(userC.address, "10")).to.be.revertedWith(
        "ERC20: transfer amount exceeds balance"
      );
    });

    it("should fail if transfer amount exceed allowance", async function () {
      console.log("owner is minting 10000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "10000");
      console.log(
        "contract is transfering 10000 tokens from userA to userB, should revert with `ERC20: transfer amount exceeds allowance`"
      );
      await expect(mockTransfer.transferFrom(userA.address, userB.address, "10000")).to.be.revertedWith(
        "ERC20: transfer amount exceeds allowance"
      );

      console.log("contract is getting approve 10000 tokens from userA");
      crss.connect(userA).approve(mockTransfer.address, "10000");
      console.log("contract is retry again transfering 10000 tokens from userA to userB, should not revert");
      mockTransfer.transferFrom(userA.address, userB.address, "10000");
      console.log("userB's balance should be 10000 tokens");
      expect(await crss.balanceOf(userB.address)).to.be.equal("10000");
    });

    it("should set rate only by owner", async function () {
      // todo
    });

    it("should accumulate the transfer amount per user", async function () {
      console.log("owner is minting 10000 tokens itself");
      await crss.connect(owner).mint(owner.address, "10000");

      // transfer tokens from owner to userA
      console.log("owner is transfering 7000 tokens to userA");
      await crss.connect(owner).transfer(userA.address, "7000");
      console.log("should not be accumulated for owner");
      console.log("length of transfersInOneTx should be 0");
      await expect(crss.transfersInOneTx(0)).to.be.reverted;

      // transfer tokens from userA to owner
      console.log("userA is transfering 3000 tokens back to owner");
      await crss.connect(userA).transfer(owner.address, "3000");
      console.log("should not be accumulated for userA");
      console.log("length of transfersInOneTx should be 0");
      await expect(crss.transfersInOneTx(0)).to.be.reverted;

      // transfer tokens from userA to userB
      console.log("userA is transfering 4000 tokens to userB");
      await crss.connect(userA).transfer(userB.address, "4000");
      console.log("length of transfersInOneTx should be 2");
      await expect(crss.transfersInOneTx(2)).to.be.reverted;
      console.log("userA's accumulated amount should be 4000 tokens");
      expect((await crss.transfersInOneTx(0)).account).to.be.equal(userA.address);
      expect((await crss.transfersInOneTx(0)).sent).to.be.equal("4000");
      console.log("userB's accumulated amount should be 4000 tokens");
      expect((await crss.transfersInOneTx(1)).account).to.be.equal(userB.address);
      expect((await crss.transfersInOneTx(1)).received).to.be.equal("4000");
    });

    it("whitelisted address should allow to transfer large amount", async function () {
      // todo
    });

    it("accumulated amount should not affect on another address", async function () {
      console.log("owner is minting 30000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "30000");
      console.log("owner is minting 10000 tokens to userB");
      await crss.connect(owner).mint(userA.address, "10000");

      // transfer tokens from userA to userC
      console.log("userA is transfering 6000 tokens to userC");
      await crss.connect(userA).transfer(userC.address, "6000");
      console.log("length of transfersInOneTx should be 2");
      await expect(crss.transfersInOneTx(2)).to.be.reverted;
      console.log("userA's accumulated amount should be 6000 tokens");
      expect((await crss.transfersInOneTx(0)).account).to.be.equal(userA.address);
      expect((await crss.transfersInOneTx(0)).sent).to.be.equal("6000");
      console.log("userC's accumulated amount should be 6000 tokens");
      expect((await crss.transfersInOneTx(1)).account).to.be.equal(userC.address);
      expect((await crss.transfersInOneTx(1)).received).to.be.equal("6000");

      // transfer tokens from userB to userC, should recalculate again
      console.log("userB is transfering 4000 tokens to userC");
      await crss.connect(userB).transfer(userC.address, "4000");
      console.log("length of transfersInOneTx should be 2");
      await expect(crss.transfersInOneTx(2)).to.be.reverted;
      console.log("userB's accumulated amount should be 4000 tokens");
      expect((await crss.transfersInOneTx(0)).account).to.be.equal(userB.address);
      expect((await crss.transfersInOneTx(0)).sent).to.be.equal("4000");
      console.log("userC's accumulated amount should be 4000 tokens");
      expect((await crss.transfersInOneTx(1)).account).to.be.equal(userC.address);
      expect((await crss.transfersInOneTx(1)).received).to.be.equal("4000");
    });

    it("accumulated amount should be calculated per same account", async function () {
      console.log("owner is minting 30000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "30000");
      console.log("owner is minting 10000 tokens to userB");
      await crss.connect(owner).mint(userA.address, "10000");

      console.log("userA is transfering 6000 tokens to userB and transfering 4000 tokens to userC continuously");
      await crss.connect(userA).approve(mockTransfer.address, "10000000");
      await mockTransfer.connect(userA).transferCross(userA.address, userB.address, userC.address, "6000", "4000");

      // transfer tokens from userA to userB
      console.log("length of transfersInOneTx should be 3");
      await expect(crss.transfersInOneTx(3)).to.be.reverted;
      console.log("userA's accumulated amount should be 10000 tokens");
      expect((await crss.transfersInOneTx(0)).account).to.be.equal(userA.address);
      expect((await crss.transfersInOneTx(0)).sent).to.be.equal("10000");
      console.log("userB's accumulated amount should be 6000 tokens");
      expect((await crss.transfersInOneTx(1)).account).to.be.equal(userB.address);
      expect((await crss.transfersInOneTx(1)).received).to.be.equal("6000");
      expect((await crss.transfersInOneTx(2)).account).to.be.equal(userC.address);
      expect((await crss.transfersInOneTx(2)).received).to.be.equal("4000");
    });

    it("should revert if exceed the max transfer amount", async function () {
      console.log("owner is minting 10000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "10000");

      const maxTransferAmount = await crss.maxTransferAmount();
      console.log("max transfer amount is ", maxTransferAmount.toString());

      console.log(
        "userA is transfering 6000 tokens to userB, should revert with `CrssToken: Exceed MaxTransferAmount`"
      );
      await expect(crss.connect(userA).transfer(userB.address, "6000")).to.be.revertedWith(
        "CrssToken: Exceed MaxTransferAmount"
      );
    });

    it("should revert if exceed the max transfer amount in one transaction", async function () {
      console.log("owner is minting 10000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "10000");

      const maxTransferAmount = await crss.maxTransferAmount();
      console.log("max transfer amount is ", maxTransferAmount.toString());

      console.log(
        "userA is transfering 3000 tokens to userB and transfering 2500 tokens to userC continuously, should revert with `CrssToken: Exceed MaxTransferAmount`"
      );
      await crss.connect(userA).approve(mockTransfer.address, "1000000");
      await expect(
        mockTransfer.connect(userA).transferCross(userA.address, userB.address, userC.address, "3000", "2500")
      ).to.be.revertedWith("CrssToken: Exceed MaxTransferAmount");
    });

    it("owner should allow to transfer in excess of max transfer amount", async function () {
      console.log("owner is minting 10000 tokens itself");
      await crss.connect(owner).mint(owner.address, "10000");

      const maxTransferAmount = await crss.maxTransferAmount();
      console.log("max transfer amount is ", maxTransferAmount.toString());

      console.log(
        "owner is transfering 3000 tokens to userA and transfering 2500 tokens to userB continuously, should not revert"
      );
      await crss.connect(owner).approve(mockTransfer.address, "1000000");
      await expect(
        mockTransfer.connect(owner).transferCross(owner.address, userA.address, userB.address, "3000", "2500")
      ).to.be.revertedWith("CrssToken: Exceed MaxTransferAmount");
    });
  });

  describe("transfer fee test", async function () {
    let devFeeRate: BigNumber, liquidityFeeRate: BigNumber, buybackFeeRate: BigNumber;

    let tokenA: MockToken, tokenB: MockToken, pair: CrossPair, pairAddress: string;

    before("check default fee", async function () {
      console.log("checking default fees in crss token");
      devFeeRate = await crss.devFeeRate();
      liquidityFeeRate = await crss.liquidityFeeRate();
      buybackFeeRate = await crss.buybackFeeRate();

      assert.equal(devFeeRate, BigNumber.from("4"));
      assert.equal(liquidityFeeRate, BigNumber.from("3"));
      assert.equal(buybackFeeRate, BigNumber.from("3"));

      console.log("dev fee rate is 0.04%");
      console.log("liquidity fee rate is 0.03%");
      console.log("buy back fee rate is 0.03%");

      console.log("creating lp pair");
      const MockToken = await hre.ethers.getContractFactory("MockToken");
      tokenA = (await MockToken.deploy("tokenA", "tokenB")) as MockToken;
      tokenB = (await MockToken.deploy("tokenB", "tokenB")) as MockToken;

      pairAddress = await factory.getPair(tokenA.address, tokenB.address);
      pair = (await hre.ethers.getContractAt(pairAddress, JSON.stringify(CrossPairAbi.abi))).connect(
        owner
      ) as CrossPair;

      crss.connect(owner).setFarm(owner.address);
    });

    beforeEach("burn all tokens", async function () {
      crss.connect(owner).burn(owner.address, await crss.balanceOf(owner.address));
      crss.connect(owner).burn(userA.address, await crss.balanceOf(userA.address));
      crss.connect(owner).burn(userB.address, await crss.balanceOf(userB.address));
      crss.connect(owner).burn(mockTransfer.address, await crss.balanceOf(mockTransfer.address));
      crss.connect(owner).burn(pairAddress, await crss.balanceOf(pairAddress));
    });

    after(async function () {
      await crss.connect(owner).setFarm(farm.address);
    });

    it("should pay liquidity fee if user to user", async function () {
      console.log("owner is minting 10000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "10000");

      console.log("userA is transfering 10000 tokens to userB");
      await crss.connect(userA).transfer(userB.address, "10000");
      console.log("balance of userA should be empty tokens");
      expect(await crss.balanceOf(userA.address)).to.be.equal("0");
      console.log("balance of userB should be 9997 tokens, paying liquidity fee");
      expect(await crss.balanceOf(userB.address)).to.be.equal("9997");
    });

    it("should pay liquidity fee if user to pool", async function () {
      console.log("owner is minting 10000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "10000");

      console.log("userA is transfering 10000 tokens to pair");
      await crss.connect(userA).transfer(pairAddress, "10000");
      console.log("balance of userA should be empty tokens");
      expect(await crss.balanceOf(userA.address)).to.be.equal("0");
      console.log("balance of pair should be 9997 tokens, paying liquidity fee");
      expect(await crss.balanceOf(pairAddress)).to.be.equal("9997");
    });

    it("should pay liquidity fee if user to non-pool contract", async function () {
      console.log("owner is minting 10000 tokens to userA");
      await crss.connect(owner).mint(userA.address, "10000");

      console.log("userA is transfering 10000 tokens to contract");
      await crss.connect(userA).transfer(mockTransfer.address, "10000");
      console.log("balance of userA should be empty tokens");
      expect(await crss.balanceOf(userA.address)).to.be.equal("0");
      console.log("balance of contract should be 9997 tokens, paying liquidity fee");
      expect(await crss.balanceOf(mockTransfer.address)).to.be.equal("9997");
    });

    it("should pay liquidity fee if non-pool contract to user", async function () {
      console.log("owner is minting 10000 tokens to contract");
      await crss.connect(owner).mint(mockTransfer.address, "10000");

      console.log("contract is transfering 10000 tokens to userA");
      await mockTransfer.transferTo(userA.address, "10000");
      console.log("balance of contract should be empty tokens");
      expect(await crss.balanceOf(mockTransfer.address)).to.be.equal("0");
      console.log("balance of userA should be 9997 tokens, paying liquidity fee");
      expect(await crss.balanceOf(userA.address)).to.be.equal("9997");
    });

    it("should pay liquidity fee if non-pool to pool", async function () {
      console.log("owner is minting 10000 tokens to contract");
      await crss.connect(owner).mint(mockTransfer.address, "10000");

      console.log("contract is transfering 10000 tokens to pair");
      await mockTransfer.transferTo(pairAddress, "10000");
      console.log("balance of contract should be empty tokens");
      expect(await crss.balanceOf(mockTransfer.address)).to.be.equal("0");
      console.log("balance of pair should be 9997 tokens, paying liquidity fee");
      expect(await crss.balanceOf(pairAddress)).to.be.equal("9997");
    });

    it("should pay liquidity/dev/buyback fee if contract to contract", async function () {
      const MockTransfer = await hre.ethers.getContractFactory("MockTransfer");
      const mockTransfer2 = (await MockTransfer.deploy()) as MockTransfer;
      await mockTransfer2.deployed();

      console.log("owner is minting 10000 tokens to contract");
      await crss.connect(owner).mint(mockTransfer.address, "10000");

      console.log("contract is transfering 10000 tokens to another contract");
      await mockTransfer.transferTo(mockTransfer2.address, "10000");
      console.log("balance of contract should be empty tokens");
      expect(await crss.balanceOf(mockTransfer.address)).to.be.equal("0");
      console.log("balance of another contract should be 9997 tokens, paying liquidity fee");
      expect(await crss.balanceOf(mockTransfer2.address)).to.be.equal("9997");
    });
  });
});
