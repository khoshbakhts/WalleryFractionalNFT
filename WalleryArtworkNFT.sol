// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title WalleryArtworkNFT
 * @notice NFT قرارداد آثار هنری پروژه Wallery
 * @dev مبتنی بر ERC721URIStorage و ERC2981 (Royalties)
 * کاملاً سازگار با OpenZeppelin Contracts v5.x
 */

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract WalleryArtworkNFT is ERC721URIStorage, ERC2981, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdTracker;

    event ArtworkMinted(address indexed to, uint256 indexed tokenId, string tokenURI_);
    event DefaultRoyaltySet(address indexed receiver, uint96 feeNumerator);
    event TokenRoyaltySet(uint256 indexed tokenId, address indexed receiver, uint96 feeNumerator);

    constructor(
        string memory name_,
        string memory symbol_,
        address defaultRoyaltyReceiver,
        uint96 defaultRoyaltyFeeNumerator
    )
        ERC721(name_, symbol_)
        Ownable(msg.sender)
    {
        if (defaultRoyaltyReceiver != address(0) && defaultRoyaltyFeeNumerator > 0) {
            _setDefaultRoyalty(defaultRoyaltyReceiver, defaultRoyaltyFeeNumerator);
            emit DefaultRoyaltySet(defaultRoyaltyReceiver, defaultRoyaltyFeeNumerator);
        }
    }

    /**
     * @notice مینت اثر جدید
     */
    function safeMint(address to, string calldata tokenURI_) external onlyOwner returns (uint256 tokenId) {
        _tokenIdTracker.increment();
        tokenId = _tokenIdTracker.current();

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);

        emit ArtworkMinted(to, tokenId, tokenURI_);
    }

    /**
     * @notice سوزاندن NFT توسط مالک یا آدرس دارای مجوز
     */
    function burn(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        bool isApproved =
            (_msgSender() == owner) ||
            (getApproved(tokenId) == _msgSender()) ||
            (isApprovedForAll(owner, _msgSender()));

        require(isApproved, "Not owner nor approved");

        // در نسخه 5.x از OpenZeppelin، کافی است همین متد از ERC721URIStorage را صدا بزنیم.
        super._burn(tokenId);
    }

    /**
     * @notice تنظیم رویالتی پیش‌فرض
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
        emit DefaultRoyaltySet(receiver, feeNumerator);
    }

    /**
     * @notice حذف رویالتی پیش‌فرض
     */
    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
        emit DefaultRoyaltySet(address(0), 0);
    }

    /**
     * @notice تنظیم رویالتی خاص برای یک توکن
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit TokenRoyaltySet(tokenId, receiver, feeNumerator);
    }

    /**
     * @notice حذف رویالتی خاص یک توکن
     */
    function deleteTokenRoyalty(uint256 tokenId) external onlyOwner {
        _resetTokenRoyalty(tokenId);
        emit TokenRoyaltySet(tokenId, address(0), 0);
    }

    /**
     * @notice تعداد کل توکن‌های مینت‌شده
     */
    function mintedCount() external view returns (uint256) {
        return _tokenIdTracker.current();
    }

    // ----------------- Overrides -----------------

    /// @dev فقط پشتیبانی از اینترفیس‌ها لازم است
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
