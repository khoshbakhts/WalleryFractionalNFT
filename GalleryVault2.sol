// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC721/IERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC721/IERC721Receiver.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/access/Ownable.sol";


interface IArtShareToken {
    function mintTo(address to, uint256 amount) external;
    function MAX_SUPPLY() external view returns (uint256);
}

contract GalleryVault is IERC721Receiver, Ownable {
    IERC721 public immutable artworkNFT;
    IArtShareToken public immutable shareToken;

    uint256[] private _artworkTokenIds;
    bool public isFinalized;

    event ArtworkReceived(uint256 indexed tokenId);
    event Fractionalized(address indexed receiver, uint256 amount);

    constructor(address _artworkNFT, address _shareToken) Ownable(msg.sender) {
        require(_artworkNFT != address(0), "GalleryVault: zero artwork address");
        require(_shareToken != address(0), "GalleryVault: zero token address");

        artworkNFT = IERC721(_artworkNFT);
        shareToken = IArtShareToken(_shareToken);
    }

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(
            msg.sender == address(artworkNFT),
            "GalleryVault: only configured NFT contract"
        );

        _artworkTokenIds.push(tokenId);
        emit ArtworkReceived(tokenId);

        return this.onERC721Received.selector;
    }

    function getArtworkTokenIds() external view returns (uint256[] memory) {
        return _artworkTokenIds;
    }

    function fractionalize() external onlyOwner {
        require(!isFinalized, "GalleryVault: already finalized");

        for (uint256 i = 0; i < _artworkTokenIds.length; i++) {
            uint256 tokenId = _artworkTokenIds[i];
            require(
                artworkNFT.ownerOf(tokenId) == address(this),
                "GalleryVault: vault not owner of all NFTs"
            );
        }

        uint256 amount = shareToken.MAX_SUPPLY();
        shareToken.mintTo(owner(), amount);

        isFinalized = true;
        emit Fractionalized(owner(), amount);
    }
}
