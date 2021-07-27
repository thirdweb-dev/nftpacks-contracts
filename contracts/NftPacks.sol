// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./IPack.sol";

contract NftPacks is ERC1155PresetMinterPauser, ERC721Holder {

  /// @dev $PACK Protocol's pack contract.
  IPack internal pack;

  /// @dev The token Id of the reward to mint.
  uint public nextTokenId;

  enum UnderlyingType { None, ERC721 }

  struct Reward {
    address creator;
    string uri;
    uint supply;
    UnderlyingType underlyingType;
  }

  struct ERC721Reward {
    address nftContract;
    uint nftTokenId;
  }

  /// @notice Reward Events.
  event NativeRewards(address indexed creator, uint[] rewardIds, string[] rewardURIs, uint[] rewardSupplies);
  event ERC721Rewards(address indexed creator, address indexed nftContract, uint nftTokenId, uint rewardTokenId, string rewardURI);
  event ERC721Redeemed(address indexed redeemer, address indexed nftContract, uint nftTokenId, uint rewardTokenId);

  /// @notice Airdrop events
  event MerkleRoot(uint indexed packId, bytes32 merkleRoot);
  event AirdropClaimed(uint indexed packId, address claimer, uint amount);

  /// @dev Reward tokenId => Reward state.
  mapping(uint => Reward) public rewards;

  /// @dev Reward tokenId => Underlying ERC721 reward state.
  mapping(uint => ERC721Reward) public erc721Rewards;

  /// @dev Pack Id => airdrop merkle tree root.
  mapping(uint => bytes32) public merkleRoot;

  /// @dev Address => pack Id => whether the airdrop was claimed.
  mapping(address => mapping(uint => bool)) public claimed;

  constructor(address _pack) ERC1155PresetMinterPauser("") {
    _setRoleAdmin(MINTER_ROLE, MINTER_ROLE);
    pack = IPack(_pack);
  }

  /// @notice Create native ERC 1155 rewards.
  function createNativeRewards(string[] calldata _rewardURIs, uint[] calldata _rewardSupplies) external returns (uint[] memory rewardIds) {
    require(_rewardURIs.length == _rewardSupplies.length, "Rewards: Must specify equal number of URIs and supplies.");
    require(_rewardURIs.length > 0, "Rewards: Must create at least one reward.");

    // Get tokenIds.
    rewardIds = new uint[](_rewardURIs.length);
    
    // Store reward state for each reward.
    for(uint i = 0; i < _rewardURIs.length; i++) {
      rewardIds[i] = nextTokenId;

      rewards[nextTokenId] = Reward({
        creator: msg.sender,
        uri: _rewardURIs[i],
        supply: _rewardSupplies[i],
        underlyingType: UnderlyingType.None
      });

      nextTokenId++;
    }

    // Mint reward tokens to `msg.sender`
    _setupRole(MINTER_ROLE, msg.sender);
    mintBatch(msg.sender, rewardIds, _rewardSupplies, "");
    revokeRole(MINTER_ROLE, msg.sender);

    emit NativeRewards(msg.sender, rewardIds, _rewardURIs, _rewardSupplies);
  }

  /// @dev Wraps an ERC721 NFT as ERC1155 reward tokens. 
  function wrapERC721(address _nftContract, uint _tokenId, string calldata _rewardURI) external {
    require(
      IERC721(_nftContract).ownerOf(_tokenId) == msg.sender,
      "Rewards: Only the owner of the NFT can wrap it."
    );
    require(
      IERC721(_nftContract).getApproved(_tokenId) == address(this) || IERC721(_nftContract).isApprovedForAll(msg.sender, address(this)),
      "Rewards: Must approve the contract to transfer the NFT."
    );
        
    // Transfer the NFT to this contract.
    IERC721(_nftContract).safeTransferFrom(
      msg.sender, 
      address(this), 
      _tokenId
    );

    // Mint reward tokens to `msg.sender`
    _setupRole(MINTER_ROLE, msg.sender);
    mint(msg.sender, nextTokenId, 1, "");
    revokeRole(MINTER_ROLE, msg.sender); 

    // Store reward state.
    rewards[nextTokenId] = Reward({
      creator: msg.sender,
      uri: _rewardURI,
      supply: 1,
      underlyingType: UnderlyingType.ERC721
    });       
        
    // Map the reward tokenId to the underlying NFT
    erc721Rewards[nextTokenId] = ERC721Reward({
      nftContract: _nftContract,
      nftTokenId: _tokenId
    });

    emit ERC721Rewards(msg.sender, _nftContract, _tokenId, nextTokenId, _rewardURI);

    nextTokenId++;
  }
  
  /// @dev Lets the reward owner redeem their ERC721 NFT.
  function redeemERC721(uint _rewardId) external {
    require(balanceOf(msg.sender, _rewardId) > 0, "Rewards: Cannot redeem a reward you do not own.");
        
    // Burn the reward token
    burn(msg.sender, _rewardId, 1);
        
    // Transfer the NFT to `msg.sender`
    IERC721(erc721Rewards[_rewardId].nftContract).safeTransferFrom(
      address(this), 
      msg.sender,
      erc721Rewards[_rewardId].nftTokenId
    );

    emit ERC721Redeemed(msg.sender, erc721Rewards[_rewardId].nftContract, erc721Rewards[_rewardId].nftTokenId, _rewardId);
  }

  /// @dev Creates packs with rewards.
  function createPack(string calldata _packURI, uint[] calldata _rewardIds, uint[] calldata _rewardAmounts) external returns (uint packId, uint packTotalSupply) {
    (packId, packTotalSupply) = pack.createPack(_packURI, address(this), _rewardIds, _rewardAmounts, 0, 0);
  }

  /// @dev Set the merkle root for the pack airdrop
  function setMerkleRoot(bytes32 _merkleRoot, uint _packId) external {
    require(pack.creator(_packId) == msg.sender, "Only the creator of a pack can set its airdrop merkle root.");

    merkleRoot[_packId] = _merkleRoot;
    emit MerkleRoot(_packId, _merkleRoot);
  }

  /// @dev Lets an address claim a pack from the airdrop
  function claimAirdrop(uint _packId, bytes32[] memory _proof) external {
    
    bytes32 leaf = bytes32(uint256(uint160(msg.sender)));

    // Check eligibility for airdrop.
    require(verify(merkleRoot[_packId], leaf, _proof), "NFT Packs: address not eligible for airdrop.");
    require(!claimed[msg.sender][_packId], "NFT Packs: address has already claimed airdrop.");

    // Update claim status
    claimed[msg.sender][_packId] = true;

    // Transfer 1 pack to caller.
    pack.safeTransferFrom(address(this), msg.sender, _packId, 1, "");

    emit AirdropClaimed(_packId, msg.sender, 1);
  }

  /// @dev Lets the creator of a pack claim away all packs.
  function claimAllRemaining(uint _packId) external {
    require(pack.creator(_packId) == msg.sender, "Only the creator of a pack can claim away all packs.");

    uint packBalance = pack.balanceOf(address(this), _packId);

    // Transfer all packs to caller.
    pack.safeTransferFrom(address(this), msg.sender, _packId, packBalance, "");

    emit AirdropClaimed(_packId, msg.sender, packBalance);
  }

  function verify(
    bytes32 root,
    bytes32 leaf,
    bytes32[] memory proof
  )
    internal
    pure
    returns (bool)
  {
    bytes32 computedHash = leaf;

    for (uint256 i = 0; i < proof.length; i++) {
      bytes32 proofElement = proof[i];

      if (computedHash < proofElement) {
        // Hash(current computed hash + current element of the proof)
        computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
      } else {
        // Hash(current element of the proof + current computed hash)
        computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
      }
    }

    // Check if the computed hash (root) is equal to the provided root
    return computedHash == root;
  }

  /// @dev Updates a token's total supply.
  function _beforeTokenTransfer(
    address,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory
  )
    internal
    override
  {
    // Decrease total supply if tokens are being burned.
    if (to == address(0)) {

      for(uint i = 0; i < ids.length; i++) {
        rewards[ids[i]].supply -= amounts[i];
      }
    }
  }

  /// @dev See EIP 1155
  function uri(uint _rewardId) public view override returns (string memory) {
    return rewards[_rewardId].uri;
  }

  /// @dev Returns the creator of reward token
  function creator(uint _rewardId) external view returns (address) {
    return rewards[_rewardId].creator;
  }
}