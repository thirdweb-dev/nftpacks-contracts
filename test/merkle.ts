import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Signer, Contract, ContractFactory, BigNumber } from "ethers";

import keccak256 from 'keccak256'
import { MerkleTree } from 'merkletreejs'

describe("Test entire NFT Packs flow", function () {

  // Signers
  let deployer: Signer;
  let creator: Signer;
  let goodClaimer: Signer;
  let badClaimer: Signer;

  // Contracts
  let nftpacks: Contract;
  let airdropCenter: Contract;
  let packContract: Contract;
  let nftContract: Contract;

  // Merkle tree
  let leaves: any;
  let tree: any;
  let root: any;


  // Parameters
  const numOfNFTs: number = 10;
  const totalRewards: number = 1000;
  const rewardIds: BigNumber[] = [];
  const rewardSupplies: BigNumber[] = [];

  const expectedPackId: BigNumber = BigNumber.from(0);

  before(async () => {
    // Get signers
    [deployer, creator, goodClaimer, badClaimer] = await ethers.getSigners();

    // Get contracts

    const Pack_Factory: ContractFactory = await ethers.getContractFactory("Pack");
    packContract = await Pack_Factory.deploy("$PACK Protocol");

    const NftPacks_Factory: ContractFactory = await ethers.getContractFactory("NftPacks");
    nftpacks = await NftPacks_Factory.deploy(packContract.address);

    const Nft_Factory: ContractFactory = await ethers.getContractFactory("NFT");
    nftContract = await Nft_Factory.connect(creator).deploy();

    // Initialize NFT Packs
    await nftpacks.init();

    // Get Airdrop safe
    const airdropCenterAddr: string = await nftpacks.airdropCenter();
    airdropCenter = await ethers.getContractAt("Airdrop", airdropCenterAddr)

    // Mint nfts and create ERC 721 rewards

    await nftContract.connect(creator).setApprovalForAll(nftpacks.address, true);

    for(let i = 0; i < numOfNFTs; i ++) {
      // mint nft
      await nftContract.mint(await creator.getAddress());
      
      // create reward
      await nftpacks.connect(creator).createERC721Rewards(nftContract.address, i, `Dummy reward URI ${i}`);

      rewardIds.push(BigNumber.from(i));
      rewardSupplies.push(BigNumber.from(1));
    }

    // Create participation reward;
    await nftpacks.connect(creator).createNativeRewards(["Participation reward"], [totalRewards - numOfNFTs]);
    rewardIds.push(
      rewardIds[rewardIds.length - 1].add(BigNumber.from(1))
    )
    rewardSupplies.push(BigNumber.from(totalRewards - numOfNFTs));

    // Create pack
    await airdropCenter.connect(creator).createPack("Dummy pack URI", rewardIds, rewardSupplies);

    // Create airdrop merkle tree.
    const addresses: string[] = [];
    addresses.push(await goodClaimer.getAddress())
    addresses.push(await creator.getAddress())
    addresses.push(await deployer.getAddress())
    
    leaves = addresses.map(x => keccak256(x));
    tree = new MerkleTree(leaves, keccak256, { sort: true });
    root = tree.getHexRoot()
    
    // Set merkleTree root for packId
    await airdropCenter.connect(creator).setMerkleRoot(root, expectedPackId);
  })

  it("Should let the good claimer claim the airdrop", async () => {

    expect(await packContract.balanceOf(await goodClaimer.getAddress(), expectedPackId)).to.equal(0);

    const proof = tree.getHexProof(
      ethers.utils.keccak256(await goodClaimer.getAddress())
    )

    await airdropCenter.connect(goodClaimer).claimAirdrop(proof, expectedPackId);

    expect(await packContract.balanceOf(await goodClaimer.getAddress(), expectedPackId)).to.equal(1);

    await expect(airdropCenter.connect(goodClaimer).claimAirdrop(proof, expectedPackId))
      .to.be.revertedWith("NFT Packs: address has already claimed airdrop.");
  })

  it("Should not let the bad claimer claim the airdrop", async () => {
    const proof = tree.getHexProof(
      ethers.utils.keccak256(await badClaimer.getAddress())
    )

    await expect(airdropCenter.connect(badClaimer).claimAirdrop(proof, expectedPackId))
      .to.be.revertedWith("NFT Packs: address not eligible for airdrop.");
  })
})