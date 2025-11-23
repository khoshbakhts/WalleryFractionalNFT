// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/access/Ownable.sol";

contract WalleryArtworkNFT is ERC721URIStorage, Ownable {
    uint256 public nextTokenId;

    event ArtworkMinted(uint256 indexed tokenId, address indexed to, string uri);

    constructor() ERC721("Wallery Artwork", "WART") Ownable(msg.sender) {}

    function mintArtwork(address to, string memory uri) external onlyOwner {
        uint256 tokenId = ++nextTokenId;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit ArtworkMinted(tokenId, to, uri);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "";
    }
}
