// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GalleryVaultFactory
 * @notice کارخانه ساخت Vault برای کسری‌سازی آثار هنری
 * @dev سازگار با OpenZeppelin v5.x و Remix
 *
 * امکانات:
 *  - createVault(): ساخت یک GalleryVault جدید برای (artwork, tokenId)
 *  - رجیستری mapping برای جستجو و جلوگیری از تکرار
 *  - لیست همه Vaultها و دسترسی‌های کمکی
 *  - سوییچ ایجاد عمومی (publicCreate) قابل تنظیم توسط owner
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "./GalleryVault.sol";

contract GalleryVaultFactory is Ownable {
    /// @notice آیا ساخت Vault برای عموم باز است؟
    bool public publicCreate = true;

    /// @notice نگاشت یکتا: (artwork, tokenId) → آدرس Vault
    mapping(address => mapping(uint256 => address)) private _vaultOf;

    /// @notice لیست همه Vaultهای ساخته‌شده
    address[] private _allVaults;

    /// رویداد ساخت Vault جدید
    event VaultCreated(
        address indexed vault,
        address indexed artwork,
        uint256 indexed tokenId,
        address owner,
        string shareName,
        string shareSymbol,
        uint8 shareDecimals,
        uint256 totalShares,
        address initialHolder
    );

    constructor(address owner_) Ownable(owner_) {}

    // ---------------------------------------------------------------------
    // Create
    // ---------------------------------------------------------------------

    /**
     * @notice ساخت Vault جدید برای یک اثر (NFT)
     * @param owner_ مالک Vault (گالری/ادمین)
     * @param artwork آدرس قرارداد NFT (WalleryArtworkNFT)
     * @param tokenId شناسه NFT
     * @param shareName نام توکن سهام (مثلاً "Mona Lisa Shares")
     * @param shareSymbol نماد توکن سهام (مثلاً "MLS")
     * @param shareDecimals تعداد اعشار توکن سهام (مثلاً 18)
     * @param totalShares عرضه کل سهام (با درنظر گرفتن decimals)
     * @param initialHolder دریافت‌کننده اولیه سهام
     *
     * نکته:
     *  - اگر publicCreate = false باشد، فقط owner کارخانه می‌تواند بسازد.
     *  - برای جلوگیری از تکرار، اگر قبلاً Vault برای این (artwork, tokenId) وجود داشته باشد، revert می‌شود.
     */
    function createVault(
        address owner_,
        address artwork,
        uint256 tokenId,
        string calldata shareName,
        string calldata shareSymbol,
        uint8 shareDecimals,
        uint256 totalShares,
        address initialHolder
    ) external returns (address vault) {
        if (!publicCreate) {
            require(msg.sender == owner(), "GVF: public create disabled");
        }
        require(artwork != address(0), "GVF: bad NFT");
        require(owner_ != address(0), "GVF: bad vault owner");
        require(initialHolder != address(0), "GVF: bad initial holder");
        require(_vaultOf[artwork][tokenId] == address(0), "GVF: vault exists");

        // ساخت Vault جدید
        GalleryVault v = new GalleryVault(
            owner_,
            artwork,
            tokenId,
            shareName,
            shareSymbol,
            shareDecimals,
            totalShares,
            initialHolder
        );
        vault = address(v);

        // ثبت در رجیستری
        _vaultOf[artwork][tokenId] = vault;
        _allVaults.push(vault);

        emit VaultCreated(
            vault,
            artwork,
            tokenId,
            owner_,
            shareName,
            shareSymbol,
            shareDecimals,
            totalShares,
            initialHolder
        );
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    /**
     * @notice روشن/خاموش کردن امکان ساخت عمومی
     * @param enabled مقدار جدید
     * @dev فقط owner کارخانه
     */
    function setPublicCreate(bool enabled) external onlyOwner {
        publicCreate = enabled;
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice آدرس Vault مرتبط با یک (artwork, tokenId) را برمی‌گرداند (اگر وجود داشته باشد)
    function getVault(address artwork, uint256 tokenId) external view returns (address) {
        return _vaultOf[artwork][tokenId];
    }

    /// @notice تعداد کل Vaultهای ساخته‌شده
    function vaultsLength() external view returns (uint256) {
        return _allVaults.length;
    }

    /// @notice دریافت Vault در اندیس مشخص
    function vaultAt(uint256 index) external view returns (address) {
        require(index < _allVaults.length, "GVF: out of bounds");
        return _allVaults[index];
    }

    /// @notice لیست کامل Vaultها (برای UIهای کوچک؛ در پروژه‌های بزرگ بهتر است paginate کنید)
    function allVaults() external view returns (address[] memory) {
        return _allVaults;
    }
}
