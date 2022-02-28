
# NFT Packs: contracts

NFT Packs is a tool for NFT giveaways. Bundle [ERC 721](https://eips.ethereum.org/EIPS/eip-721) NFTs as rewards into
packs and airdrop them to an audience.

On opening a pack, the opener will receive either one of the reward NFTs or
an [ERC 1155](https://eips.ethereum.org/EIPS/eip-1155) for participating in the giveaway.

NFT Packs is powered by [$PACK Protocol](https://nkrishang.gitbook.io/pack-protocol/).

### Quick Example
You have 10 ERC 721 NFTs you want to giveaway.

You bundle those 10 NFTs into a total of 1000 packs and airdrop them
to an audience.

10% of those packs i.e. 10 packs will yield a reward NFT on opening. The rest
will yield an ERC 1155 NFT as a proof of participating in the givaway.

# Contracts

## Rinkeby

- `NftPacks.sol`: [0xa0ECfB332A278572CE9a98f4EE95EB79fcE2a870](https://rinkeby.etherscan.io/address/0xa0ECfB332A278572CE9a98f4EE95EB79fcE2a870#code)
- `Airdrop.sol`: [0x619c801cF0AFe3BEe2795340c9407fd4f0bbe1E3](https://rinkeby.etherscan.io/address/0x619c801cF0AFe3BEe2795340c9407fd4f0bbe1E3#code)
## Run Locally

Clone the project

```bash
  git clone https://github.com/nftlabs/nftpacks-contracts.git
```

Go to the project directory

```bash
  cd nftpacks-contracts
```

Install dependencies

```bash
  yarn install
```

Create a `.env` file with `.env.example` as reference. Then:

Run hardhat tests

```bash
  npx hardhat test
```

Deploy the project to rinkeby

```bash
npx hardhat run scripts/deployer/rinkeby.ts --network rinkeby
```

  
## Authors

- [thirdweb](https://www.github.com/thirdweb-dev)
