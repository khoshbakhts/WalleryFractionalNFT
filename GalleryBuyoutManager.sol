// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GalleryBuyoutManager
 * @notice مدیریت پیشنهادهای خرید کامل (Buyout) برای Vault ها با رأی موافق از طریق قفل‌کردن سهام
 * @dev سازگار با OpenZeppelin v5.x و معماری: WalleryArtworkNFT + ArtShareToken(v1.1) + GalleryVault + Factory
 *
 * طرح رأی‌گیری:
 *  - پیشنهاددهنده (proposer) یک پیشنهاد برای یک Vault می‌سازد و معادل قیمت فعلی Vault (buyoutPriceWei) را به ETH می‌سپارد.
 *  - دارندگان توکن سهم (ArtShareToken) به میزان دلخواه، توکن خود را در این قرارداد قفل می‌کنند (approve → lock).
 *  - اگر مجموع قفل‌شده‌ها ≥ نصاب (quorumBps) از کل عرضه‌ی توکن شد و مهلت تمام نشده بود، هر کسی می‌تواند execute کند.
 *  - در اجرای موفق، این قرارداد buyout را روی Vault اجرا و ETH سپرده‌شده را پرداخت می‌کند.
 *  - توکن‌های قفل‌شده قابل برداشت هستند (قبل یا بعد از اجرا/انقضا/لغو).
 *
 * نکته:
 *  - اگر مالک Vault قیمت را در میانه راه تغییر دهد، اجرای پیشنهاد با خطا مواجه می‌شود؛
 *    در این صورت proposer می‌تواند پیشنهاد را لغو کند و ETH خود را پس بگیرد.
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./GalleryVault.sol";
import "./ArtShareToken.sol";

contract GalleryBuyoutManager is Ownable, ReentrancyGuard {
    using Address for address payable;

    // ─────────────────────────────────────────────────────────────────────────────
    // تنظیمات
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice نصاب به صورت basis points (مثل 5100 = 51%)؛ پیش‌فرض 51%
    uint16 public quorumBps = 5100; // 51.00%
    /// @notice حداکثر مدت مجاز برای یک پیشنهاد (برای محدود کردن duration های خیلی بلند)، واحد ثانیه
    uint32 public maxDuration = 14 days;

    event QuorumBpsChanged(uint16 oldBps, uint16 newBps);
    event MaxDurationChanged(uint32 oldDur, uint32 newDur);

    // ─────────────────────────────────────────────────────────────────────────────
    // دیتامدل پیشنهاد
    // ─────────────────────────────────────────────────────────────────────────────

    struct Proposal {
        // ثابت‌ها
        address vault;           // آدرس Vault هدف
        address proposer;        // پیشنهاددهنده
        address shareToken;      // آدرس ArtShareToken مرتبط با همین Vault
        uint256 priceWei;        // قیمتی که در لحظه‌ی ایجاد از Vault خوانده شده
        uint64  deadline;        // timestamp انقضا

        // وضعیت
        bool    executed;        // اجرا شده؟
        bool    canceled;        // لغو شده؟
        uint256 totalLocked;     // مجموع توکن‌های قفل‌شده

        // قفل‌ها: آدرس → مقدار قفل‌شده
        mapping(address => uint256) locked;
    }

    /// @dev شمارنده‌ی شناسه‌ی پیشنهادها
    uint256 private _proposalIdCounter;

    /// @dev storage پیشنهادها
    mapping(uint256 => Proposal) private _proposals;

    /// @notice نگهداری لیست ID های پیشنهاد برای هر Vault (برای UI)
    mapping(address => uint256[]) private _proposalIdsByVault;

    // رویدادها
    event Proposed(
        uint256 indexed proposalId,
        address indexed vault,
        address indexed proposer,
        address shareToken,
        uint256 priceWei,
        uint64  deadline
    );
    event Locked(uint256 indexed proposalId, address indexed voter, uint256 amount);
    event Unlocked(uint256 indexed proposalId, address indexed voter, uint256 amount);
    event Executed(uint256 indexed proposalId, address indexed vault, uint256 priceWei, address buyer);
    event Canceled(uint256 indexed proposalId, address indexed vault, address indexed proposer);

    constructor(address owner_) Ownable(owner_) {}

    // ─────────────────────────────────────────────────────────────────────────────
    // ساخت پیشنهاد
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * @notice ایجاد پیشنهاد خرید کامل برای یک Vault
     * @param vault آدرس Vault هدف
     * @param durationSec مدت زمان اعتبار پیشنهاد (<= maxDuration)
     * @dev باید دقیقا معادل buyoutPriceWei فعلی vault به عنوان msg.value ارسال شود.
     */
    function propose(address vault, uint32 durationSec)
        external
        payable
        nonReentrant
        returns (uint256 proposalId)
    {
        require(vault != address(0), "GBM: bad vault");
        require(durationSec > 0 && durationSec <= maxDuration, "GBM: bad duration");

        GalleryVault V = GalleryVault(vault);
        require(!V.sold(), "GBM: already sold");
        require(V.buyoutPriceWei() > 0, "GBM: price not set");
        require(msg.value == V.buyoutPriceWei(), "GBM: wrong ETH value");

        // استخراج آدرس توکن سهام از Vault
        (, , address shareTokenAddr, , , , , , ) = V.vaultInfo();
        require(shareTokenAddr != address(0), "GBM: no share token");

        proposalId = ++_proposalIdCounter;
        Proposal storage P = _proposals[proposalId];
        P.vault     = vault;
        P.proposer  = msg.sender;
        P.shareToken= shareTokenAddr;
        P.priceWei  = msg.value;
        P.deadline  = uint64(block.timestamp + durationSec);

        _proposalIdsByVault[vault].push(proposalId);

        emit Proposed(
            proposalId,
            vault,
            msg.sender,
            shareTokenAddr,
            P.priceWei,
            P.deadline
        );
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // رأی موافق = قفل‌کردن سهام
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * @notice قفل کردن مقدار مشخصی از سهام به‌عنوان رأی موافق
     * @dev نیاز به approve(این قرارداد, amount) روی ArtShareToken دارد.
     */
    function lock(uint256 proposalId, uint256 amount) external nonReentrant {
        require(amount > 0, "GBM: zero amount");
        Proposal storage P = _proposalsMustBeActive(proposalId);

        ArtShareToken token = ArtShareToken(P.shareToken);
        token.transferFrom(msg.sender, address(this), amount);

        P.locked[msg.sender] += amount;
        P.totalLocked        += amount;

        emit Locked(proposalId, msg.sender, amount);
    }

    /**
     * @notice آزادسازی (بازپس‌گیری) بخشی/همه سهام قفل‌شده
     * @dev قبل از اجرا می‌توانید آزاد کنید؛ بعد از اجرا یا انقضا هم آزادسازی مجاز است.
     */
    function unlock(uint256 proposalId, uint256 amount) external nonReentrant {
        require(amount > 0, "GBM: zero amount");
        Proposal storage P = _proposals[proposalId];
        require(P.vault != address(0), "GBM: no proposal");

        uint256 lockedAmt = P.locked[msg.sender];
        require(lockedAmt >= amount, "GBM: insufficient locked");

        P.locked[msg.sender] = lockedAmt - amount;
        // توجه: اگر proposal اجرا شده باشد، totalLocked فقط جهت اطلاع است؛ کم‌کردنش اشکالی ندارد
        if (P.totalLocked >= amount) {
            P.totalLocked -= amount;
        } else {
            P.totalLocked = 0;
        }

        ArtShareToken(P.shareToken).transfer(msg.sender, amount);
        emit Unlocked(proposalId, msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // اجرا / لغو
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * @notice اجرای پیشنهاد در صورت رسیدن به نصاب
     * @dev هر کسی می‌تواند اجرا کند. اگر قیمت Vault عوض شده باشد، revert می‌شود.
     */
    function execute(uint256 proposalId) external nonReentrant {
        Proposal storage P = _proposalsMustBeActive(proposalId);

        // نصاب: totalLocked / totalSupply ≥ quorumBps/10000
        uint256 totalSupply = ArtShareToken(P.shareToken).totalSupply();
        require(totalSupply > 0, "GBM: bad supply");
        require(P.totalLocked * 10000 >= uint256(quorumBps) * totalSupply, "GBM: quorum not reached");

        GalleryVault V = GalleryVault(P.vault);
        require(!V.sold(), "GBM: already sold");
        require(V.buyoutPriceWei() == P.priceWei, "GBM: price changed");

        // اجرای خرید کامل روی Vault (انتقال NFT + واریز ETH)
        P.executed = true;
        // اثرات جانبی خارجی در انتهای تغییر وضعیت (Checks-Effects-Interactions)
        V.buyout{value: P.priceWei}();

        emit Executed(proposalId, P.vault, P.priceWei, msg.sender);
    }

    /**
     * @notice لغو پیشنهاد توسط پیشنهاددهنده (قبل از اجرا)
     * @dev ETH امانی به پیشنهاددهنده بازگردانده می‌شود.
     */
    function cancel(uint256 proposalId) external nonReentrant {
        Proposal storage P = _proposals[proposalId];
        require(P.vault != address(0), "GBM: no proposal");
        require(!P.executed && !P.canceled, "GBM: already finalized");
        require(msg.sender == P.proposer, "GBM: only proposer");

        P.canceled = true;
        payable(P.proposer).sendValue(P.priceWei);

        emit Canceled(proposalId, P.vault, P.proposer);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // ادمین
    // ─────────────────────────────────────────────────────────────────────────────

    function setQuorumBps(uint16 newBps) external onlyOwner {
        require(newBps > 0 && newBps <= 10000, "GBM: bad bps");
        uint16 old = quorumBps;
        quorumBps = newBps;
        emit QuorumBpsChanged(old, newBps);
    }

    function setMaxDuration(uint32 newMax) external onlyOwner {
        require(newMax >= 1 hours && newMax <= 90 days, "GBM: out of range");
        uint32 old = maxDuration;
        maxDuration = newMax;
        emit MaxDurationChanged(old, newMax);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // نماها (Views)
    // ─────────────────────────────────────────────────────────────────────────────

    function getLocked(uint256 proposalId, address account) external view returns (uint256) {
        Proposal storage P = _proposals[proposalId];
        require(P.vault != address(0), "GBM: no proposal");
        return P.locked[account];
    }

    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address vault,
            address proposer,
            address shareToken,
            uint256 priceWei,
            uint64  deadline,
            bool    executed,
            bool    canceled,
            uint256 totalLocked
        )
    {
        Proposal storage P = _proposals[proposalId];
        require(P.vault != address(0), "GBM: no proposal");

        return (
            P.vault,
            P.proposer,
            P.shareToken,
            P.priceWei,
            P.deadline,
            P.executed,
            P.canceled,
            P.totalLocked
        );
    }

    function proposalsByVault(address vault) external view returns (uint256[] memory) {
        return _proposalIdsByVault[vault];
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // کمکی‌های داخلی
    // ─────────────────────────────────────────────────────────────────────────────

    function _proposalsMustBeActive(uint256 proposalId) internal view returns (Proposal storage P) {
        P = _proposals[proposalId];
        require(P.vault != address(0), "GBM: no proposal");
        require(!P.executed && !P.canceled, "GBM: finalized");
        require(block.timestamp <= P.deadline, "GBM: expired");
    }

    // دریافت ETH (برای هر مورد غیرمنتظره، بلاک می‌کنیم)
    receive() external payable {
        revert("GBM: direct ETH not allowed");
    }
}
