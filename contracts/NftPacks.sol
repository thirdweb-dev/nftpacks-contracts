// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

// OZ Utils
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

// NftPacks modules
import "./IPack.sol";
import "./Airdrop.sol";

contract NftPacks is ERC1155, ERC721Holder {

  /// @dev $PACK Protocol's pack contract.
  IPack public pack;

  /// @dev NFT Packs airdrop contract.
  Airdrop public airdropCenter;

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

  /// @notice Events.
  event NativeRewards(address indexed creator, uint[] rewardIds, string[] rewardURIs, uint[] rewardSupplies);
  event ERC721Rewards(address indexed creator, address indexed nftContract, uint nftTokenId, uint rewardTokenId, string rewardURI);
  event ERC721Redeemed(address indexed redeemer, address indexed nftContract, uint nftTokenId, uint rewardTokenId);

  /// @dev Reward tokenId => Reward state.
  mapping(uint => Reward) public rewards;

  /// @dev Reward tokenId => Underlying ERC721 reward state.
  mapping(uint => ERC721Reward) public erc721Rewards;

  constructor(address _pack) ERC1155("") {
    // Set $PACK Protocol's pack contract.
    pack = IPack(_pack);
  }

  /// @dev Initializes NFT Packs.
  function init() external {
    // Deploy Airdrop safe.
    bytes memory _airdropBytecode = abi.encodePacked(type(Airdrop).creationCode, abi.encode(address(this), address(pack)));
    bytes32 _airdropSalt = bytes32("Airdrop safe");

    address _airdropCenter = Create2.deploy(0, _airdropSalt, _airdropBytecode);
    
    // Set Airdrop safe.
    airdropCenter = Airdrop(_airdropCenter);
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

    // Mint reward tokens to contract
    _mintBatch(address(airdropCenter), rewardIds, _rewardSupplies, "");

    emit NativeRewards(msg.sender, rewardIds, _rewardURIs, _rewardSupplies);
  }

  /// @dev Wraps an ERC721 NFT as ERC1155 reward tokens. 
  function createERC721Rewards(address _nftContract, uint _tokenId, string calldata _rewardURI) external {
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

    // Mint reward tokens to contract
    _mint(address(airdropCenter), nextTokenId, 1, "");
    
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
  function redeemERC721(uint _rewardId) external returns (address nftContract, uint nftTokenId) {
    require(balanceOf(msg.sender, _rewardId) > 0, "Rewards: Cannot redeem a reward you do not own.");
    
    nftContract = erc721Rewards[_rewardId].nftContract;
    nftTokenId = erc721Rewards[_rewardId].nftTokenId;

    // Burn the reward token
    _burn(msg.sender, _rewardId, 1);
        
    // Transfer the NFT to `msg.sender`
    IERC721(nftContract).safeTransferFrom(address(this), msg.sender, nftTokenId);

    emit ERC721Redeemed(msg.sender, erc721Rewards[_rewardId].nftContract, erc721Rewards[_rewardId].nftTokenId, _rewardId);
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