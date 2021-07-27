// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

// OZ Utils
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// NftPacks modules
import "./NftPacks.sol";
import "./IPack.sol";

contract Airdrop is ERC1155Holder {

  address public nftPacks;
  address public pack;

  /// @dev Whether the airdrop is 'free for all'
  mapping(uint => bool) public freeForAll;

  /// @dev Pack Id => airdrop merkle tree root.
  mapping(uint => bytes32) public merkleRoot;

  /// @dev Address => pack Id => whether the airdrop was claimed.
  mapping(address => mapping(uint => bool)) public claimed;

  /// @dev Pack Id => creator
  mapping(uint => address) public creator;

  /// @notice Airdrop events
  event MerkleRoot(uint indexed packId, bytes32 merkleRoot);
  event AirdropClaimed(uint indexed packId, address claimer, uint amount);

  constructor(address _nftPacks, address _pack) {
    nftPacks = _nftPacks;
    pack = _pack;

    IERC1155(_nftPacks).setApprovalForAll(_pack, true);
  }

  /// @dev Returns the underlying NFT to the creator.
  function returnUnderlyingNFT(uint _rewardId) external {
    require(NftPacks(nftPacks).creator(_rewardId) == msg.sender, "NFT Packs: only the creator can take back the NFT.");

    // Return NFT to the creator.
    (address nftContract, uint nftTokenId) = NftPacks(nftPacks).redeemERC721(_rewardId);
    IERC721(nftContract).safeTransferFrom(address(this), msg.sender, nftTokenId); 
  }

  /// @dev Creates packs with rewards.
  function createPack(string calldata _packURI, uint[] calldata _rewardIds, uint[] calldata _rewardAmounts) external {
    // Create pack
    (uint packId,) = IPack(pack).createPack(_packURI, nftPacks, _rewardIds, _rewardAmounts, 0, 0);
    
    // Set pack creator
    creator[packId] = msg.sender;
  }

  /// @dev Set the merkle root for the pack airdrop
  function setMerkleRoot(bytes32 _merkleRoot, uint _packId) external {
    require(
      IPack(pack).creator(_packId) == address(this) && creator[_packId] == msg.sender, 
      "Only the creator of a pack can set its airdrop merkle root."
    );

    merkleRoot[_packId] = _merkleRoot;
    emit MerkleRoot(_packId, _merkleRoot);
  }

  /// @dev Lets a pack creator set the airdrop as 'freefor all' or not.
  function setFreeForAll(uint _packId, bool _freeForAll) external {
    require(
      IPack(pack).creator(_packId) == address(this) && creator[_packId] == msg.sender, 
      "Only the creator of a pack can set its airdrop merkle root."
    );

    freeForAll[_packId] = _freeForAll;
  }

  /// @dev Lets an address claim a pack from the airdrop
  function claimAirdrop(bytes32[] memory _proof, uint _packId) external {
    
    if(!freeForAll[_packId]) {
      bytes32 leaf = keccak256(abi.encodePacked(msg.sender));

      // Check eligibility for airdrop.
      require(MerkleProof.verify(_proof, merkleRoot[_packId], leaf), "NFT Packs: address not eligible for airdrop.");
    }
    
    require(!claimed[msg.sender][_packId], "NFT Packs: address has already claimed airdrop.");

    // Update claim status
    claimed[msg.sender][_packId] = true;

    // Transfer 1 pack to caller.
    IERC1155(pack).safeTransferFrom(address(this), msg.sender, _packId, 1, "");

    emit AirdropClaimed(_packId, msg.sender, 1);
  }

  /// @dev Lets the creator of a pack claim away all packs.
  function claimAllRemaining(uint _packId) external {
    require(
      IPack(pack).creator(_packId) == address(this) && creator[_packId] == msg.sender, 
      "Only the creator of a pack can claim away all packs."
    );

    uint packBalance = IPack(pack).balanceOf(address(this), _packId);

    // Transfer all packs to caller.
    IPack(pack).safeTransferFrom(address(this), msg.sender, _packId, packBalance, "");

    emit AirdropClaimed(_packId, msg.sender, packBalance);
  }
}