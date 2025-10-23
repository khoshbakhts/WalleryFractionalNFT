// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GalleryVault
 * @notice خزانه‌ی نگهداری یک NFT و صدور/توزیع سهم‌های ERC-20 + مکانیزم ساده خرید کامل (buyout)
 * @dev سازگار با OpenZeppelin v5.x و Remix
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./ArtShareToken.sol";

contract GalleryVault is Ownable, ReentrancyGuard, ERC721Holder {
    using Address for address payable;

    // --- وضعیت پایه اثر ---
    address public immutable artwork;      // آدرس قرارداد NFT (WalleryArtworkNFT)
    uint256 public immutable artworkTokenId; // شناسه NFT
    bool public deposited;                 // آیا NFT قفل شده؟

    // --- توکن سهم‌ها ---
    ArtShareToken public shareToken;       // آدرس توکن ERC-20
    uint256 public immutable totalSharesPlanned; // عرضه کل برنامه‌ریزی‌شده (در زمان ساخت)
    uint8   public immutable sharesDecimals;

    // --- فروش کامل (Buyout) ---
    uint256 public buyoutPriceWei;         // قیمت خرید کامل به ETH
    bool    public sold;                   // آیا فروش کامل انجام شده؟
    uint256 public proceedsWei;            // وجوه حاصل از فروش
    uint256 public totalSharesAtSale;      // عرضه کل توکن‌ها در لحظه‌ی فروش (snap برای محاسبه پرداخت‌ها)

    // --- رویدادها ---
    event Deposited(address indexed from, address indexed nft, uint256 indexed tokenId);
    event SharesDeployed(address shareToken, string name, string symbol, uint8 decimals, uint256 totalSupply, address initialHolder);
    event BuyoutPriceSet(uint256 priceWei);
    event BoughtOut(address indexed buyer, uint256 priceWei);
    event Claimed(address indexed holder, uint256 burnedAmount, uint256 payoutWei);

    /**
     * @param owner_ مالک Vault (گالری/ادمین)
     * @param artwork_ آدرس قرارداد NFT
     * @param tokenId_ شناسه NFT
     * @param shareName نام توکن سهام (مثلاً "Mona Lisa Shares")
     * @param shareSymbol نماد توکن (مثلاً "MLS")
     * @param shareDecimals تعداد اعشار (مثلاً 18)
     * @param totalShares کل عرضه توکن سهام (با درنظر گرفتن decimals)
     * @param initialHolder دریافت‌کننده اولیه سهام پس از دیپلوی (معمولاً مالک اولیه اثر)
     *
     * نکته: NFT بعداً توسط مالک واقعی، از طریق deposit() منتقل/قفل می‌شود.
     */
    constructor(
        address owner_,
        address artwork_,
        uint256 tokenId_,
        string memory shareName,
        string memory shareSymbol,
        uint8 shareDecimals,
        uint256 totalShares,
        address initialHolder
    ) Ownable(owner_) {
        require(owner_ != address(0), "GV: bad owner");
        require(artwork_ != address(0), "GV: bad NFT");
        require(initialHolder != address(0), "GV: bad initial holder");
        require(totalShares > 0, "GV: zero shares");
        require(shareDecimals > 0 && shareDecimals <= 24, "GV: bad decimals");

        artwork = artwork_;
        artworkTokenId = tokenId_;
        totalSharesPlanned = totalShares;
        sharesDecimals = shareDecimals;

        // دیپلوی توکن سهام (v1.1 با امکان burn کنترل‌شده)
        shareToken = new ArtShareToken(
            shareName,
            shareSymbol,
            shareDecimals,
            totalShares,
            initialHolder,
            address(this),
            artwork_,
            tokenId_
        );

        emit SharesDeployed(address(shareToken), shareName, shareSymbol, shareDecimals, totalShares, initialHolder);
    }

    // ------------ فاز سپرده‌گذاری NFT ------------

    /**
     * @notice انتقال و قفل‌کردن NFT در Vault
     * @dev فراخوان باید مالک فعلی NFT باشد (یا approved)، قرارداد خودش transferFrom را انجام می‌دهد.
     *      قبل از صدا زدن، در قرارداد NFT approve(address(this), tokenId) بدهید یا setApprovalForAll.
     */
    function deposit() external nonReentrant {
        require(!deposited, "GV: already deposited");
        IERC721 nft = IERC721(artwork);
        address currentOwner = nft.ownerOf(artworkTokenId);
        require(
            msg.sender == currentOwner || nft.getApproved(artworkTokenId) == address(this),
            "GV: caller not owner/approved"
        );

        // انتقال NFT به Vault (این قرارداد ERC721Holder است و می‌تواند safeTransfer دریافت کند)
        nft.safeTransferFrom(currentOwner, address(this), artworkTokenId);

        // پس از انتقال موفق:
        require(nft.ownerOf(artworkTokenId) == address(this), "GV: transfer failed");
        deposited = true;

        emit Deposited(currentOwner, artwork, artworkTokenId);
    }

    // ------------ تنظیم قیمت و انجام Buyout ------------

    /**
     * @notice تعیین قیمت خرید کامل (به wei)
     * @dev فقط مالک Vault (گالری)؛ هر زمان قبل از فروش قابل تغییر است.
     */
    function setBuyoutPrice(uint256 priceWei) external onlyOwner {
        require(!sold, "GV: already sold");
        buyoutPriceWei = priceWei;
        emit BuyoutPriceSet(priceWei);
    }

    /**
     * @notice خرید کامل اثر (انتقال NFT + واریز ETH به Vault)
     * @dev خریدار باید دقیقاً برابر با قیمت تعیین‌شده ETH بفرستد.
     */
    function buyout() external payable nonReentrant {
        require(deposited, "GV: NFT not deposited");
        require(!sold, "GV: already sold");
        require(buyoutPriceWei > 0, "GV: price not set");
        require(msg.value == buyoutPriceWei, "GV: wrong ETH sent");

        // انتقال NFT به خریدار
        IERC721(artwork).safeTransferFrom(address(this), msg.sender, artworkTokenId);

        // ثبت وجوه و وضعیت فروش
        sold = true;
        proceedsWei = msg.value;
        // اسنپ‌شات عرضه کل در لحظه فروش (ثابت برای محاسبات پرداخت)
        totalSharesAtSale = shareToken.totalSupply();

        emit BoughtOut(msg.sender, msg.value);
    }

    // ------------ مطالبه وجوه توسط دارندگان سهم (Claim) ------------

    /**
     * @notice مطالبه ETH از محل فروش، با سوزاندن مقدار مشخصی از سهم‌ها
     * @param amount مقدار سهم برای سوزاندن (بر حسب smallest unit توکن)
     *
     * فرمول پرداخت: payout = proceedsWei * amount / totalSharesAtSale
     * - نیازمند approve( vault, amount ) روی ArtShareToken قبل از فراخوانی
     * - Vault سهم‌ها را می‌سوزاند (burn) تا دوباره قابل مطالبه نباشند
     */
    function claim(uint256 amount) external nonReentrant {
        require(sold, "GV: not sold");
        require(amount > 0, "GV: zero amount");
        require(totalSharesAtSale > 0, "GV: bad snapshot");

        // انتقال و سوزاندن سهم‌ها از دارنده (با مجوز قبلی)
        // نسخه v1.1 توکن، تابع burn کنترل‌شده توسط Vault دارد
        shareToken.burnFromVault(msg.sender, amount);

        // محاسبه و پرداخت نسبت به snapshot فروش
        uint256 payout = (proceedsWei * amount) / totalSharesAtSale;
        require(payout > 0, "GV: tiny amount");

        payable(msg.sender).sendValue(payout);

        emit Claimed(msg.sender, amount, payout);
    }

    // ------------ توابع کمکی ------------

    /// @notice اطلاعات پایه Vault
    function vaultInfo()
        external
        view
        returns (
            address artwork_,
            uint256 tokenId_,
            address shareToken_,
            bool deposited_,
            bool sold_,
            uint256 buyoutPrice_,
            uint256 proceeds_,
            uint256 totalShares_,
            uint8 sharesDecimals_
        )
    {
        return (
            artwork,
            artworkTokenId,
            address(shareToken),
            deposited,
            sold,
            buyoutPriceWei,
            proceedsWei,
            totalSharesPlanned,
            sharesDecimals
        );
    }

    /// @notice موجودی ETH در Vault (پس از فروش)
    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
