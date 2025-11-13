// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 *  ----------------------------------------------------------
 *   GalleryVault
 *   ------------------
 *   خزانه‌ی نگهدارنده‌ی NFTهای یک کالکشن
 *   + یک‌بار فراخوانی fractionalize برای مینت کردن تمام سهم‌ها
 *  ----------------------------------------------------------
 */

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC721/IERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC721/IERC721Receiver.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/access/Ownable.sol";

/// @notice اینترفیس مینیمال توکن سهم (ArtShareToken)
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

    /**
     * @param _artworkNFT آدرس قرارداد NFT (مثل WalleryArtworkNFT)
     * @param _shareToken آدرس قرارداد توکن سهم (ArtShareToken)
     */
    constructor(address _artworkNFT, address _shareToken) Ownable(msg.sender) {
        require(_artworkNFT != address(0), "GalleryVault: zero artwork address");
        require(_shareToken != address(0), "GalleryVault: zero token address");

        artworkNFT = IERC721(_artworkNFT);
        shareToken = IArtShareToken(_shareToken);
    }

    /**
     * @notice این تابع وقتی صدا زده می‌شود که یک NFT با safeTransferFrom
     *         به این قرارداد ارسال بشود.
     *         اینجا فقط tokenId را ذخیره می‌کنیم.
     */
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

    /**
     * @notice برگرداندن لیست همه‌ی tokenId های NFTهایی که داخل Vault هستند
     */
    function getArtworkTokenIds() external view returns (uint256[] memory) {
        return _artworkTokenIds;
    }

    /**
     * @notice یک‌بار فرکشنالایز:
     *         مینت کردن کل MAX_SUPPLY از توکن سهم برای owner قرارداد
     *         بعد از اجرا، isFinalized = true می‌شود و دیگر قابل تکرار نیست.
     */
    function fractionalize() external onlyOwner {
        require(!isFinalized, "GalleryVault: already finalized");

        // (اختیاری) چک کنیم که مالک تمام NFTها واقعا Vault باشد
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
