// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ArtShareToken
 * @notice توکن ERC-20 برای نمایش «سهم» از یک اثر هنری کسری‌سازی‌شده
 * @dev Fixed Supply + ERC20Permit (EIP-2612), سازگار با OpenZeppelin v5.x
 *
 * - vault: آدرس GalleryVault مرتبط با این اثر
 * - artwork: آدرس قرارداد NFT (WalleryArtworkNFT)
 * - artworkTokenId: شناسه NFT اصلی
 * - decimals: قابل تنظیم در سازنده
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract ArtShareToken is ERC20, ERC20Permit {
    /// @notice آدرس Vault که NFT در آن قفل شده
    address public immutable vault;

    /// @notice آدرس قرارداد NFT (WalleryArtworkNFT)
    address public immutable artwork;

    /// @notice شناسه NFT اصلی
    uint256 public immutable artworkTokenId;

    /// @notice تعداد اعشار توکن (به‌صورت immutable)
    uint8 private immutable _customDecimals;

    /**
     * @param name_   نام توکن (مثلاً "Mona Lisa Shares")
     * @param symbol_ نماد توکن (مثلاً "MLS")
     * @param decimals_ تعداد اعشار (مثلاً 18)
     * @param initialSupply مقدار کل عرضه (بر حسب smallest unit با توجه به decimals_)
     * @param initialHolder دریافت‌کننده اولیه کل عرضه (معمولاً مالک اولیه NFT)
     * @param vault_  آدرس Vault مرتبط
     * @param artwork_ آدرس قرارداد NFT پایه (WalleryArtworkNFT)
     * @param artworkTokenId_ شناسه NFT پایه
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply,
        address initialHolder,
        address vault_,
        address artwork_,
        uint256 artworkTokenId_
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        require(initialHolder != address(0), "AST: invalid holder");
        require(vault_ != address(0), "AST: invalid vault");
        require(artwork_ != address(0), "AST: invalid artwork");
        require(decimals_ > 0 && decimals_ <= 24, "AST: bad decimals");

        _customDecimals = decimals_;
        vault = vault_;
        artwork = artwork_;
        artworkTokenId = artworkTokenId_;

        _mint(initialHolder, initialSupply);
    }

    /**
     * @notice تعداد اعشار توکن
     */
    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    /**
     * @notice برگرداندن اطلاعات پیوند زیرساخت
     * @return vault_ آدرس Vault
     * @return artwork_ آدرس قرارداد NFT
     * @return tokenId_ شناسه NFT
     */
    function underlying()
        external
        view
        returns (address vault_, address artwork_, uint256 tokenId_)
    {
        return (vault, artwork, artworkTokenId);
    }
}
