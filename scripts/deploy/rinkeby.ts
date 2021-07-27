import { run, ethers } from "hardhat";
import { Contract, ContractFactory } from 'ethers';

async function main() {
  
  const [deployer] = await ethers.getSigners();

  // Deploy NFT packs
  const packAddress: string = "0x22B9fdC2fCeE92675Ab9398F42251A6A2cd8f7A1";

  const NftPacks_Factory: ContractFactory = await ethers.getContractFactory("NftPacks")
  const nftPacks: Contract = await NftPacks_Factory.deploy(packAddress);

  console.log("Deployed NftPacks at: ", nftPacks.address);

  // Initialize NftPacks
  const tx = await nftPacks.init()
  console.log("Initializing NftPacks: ", tx.hash);

  await tx;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });