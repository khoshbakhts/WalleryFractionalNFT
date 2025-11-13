// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 *  ----------------------------------------------------------
 *   ArtShareToken
 *   ------------------
 *   توکن ERC-20 نماینده‌ی سهم یک کالکشن هنری
 *   - 2 رقم اعشار
 *   - سقف عرضه ثابت (MAX_SUPPLY)
 *   - فقط Vault اجازه مینت دارد
 *  ----------------------------------------------------------
 */

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/access/Ownable.sol";

contract ArtShareToken is ERC20, Ownable {
    uint8 private constant _DECIMALS = 2;

    /// @notice حداکثر تعداد توکن (در smallest units با در نظر گرفتن decimals)
    uint256 public immutable MAX_SUPPLY;

    /// @notice آدرس Vault که اجازه مینت دارد
    address public vault;
    bool public vaultSet;

    event VaultSet(address indexed vault);
    event SharesMinted(address indexed to, uint256 amount);

    modifier onlyVault() {
        require(msg.sender == vault, "ArtShareToken: caller is not vault");
        _;
    }

    /**
     * @param name_ نام توکن 
     * @param symbol_ سمبل توکن 
     * @param maxSupply_ سقف عرضه در 
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(maxSupply_ > 0, "ArtShareToken: zero max supply");
        MAX_SUPPLY = maxSupply_;
    }

    /// @notice تعداد اعشار توکن (۲)
    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    /// @notice تنظیم آدرس Vault (فقط یک‌بار توسط owner)
    function setVault(address _vault) external onlyOwner {
        require(!vaultSet, "ArtShareToken: vault already set");
        require(_vault != address(0), "ArtShareToken: zero address");
        vault = _vault;
        vaultSet = true;
        emit VaultSet(_vault);
    }

    /// @notice مینت کردن توکن‌ها توسط Vault (هنگام fractionalize)
    function mintTo(address to, uint256 amount) external onlyVault {
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "ArtShareToken: exceeds max supply"
        );
        _mint(to, amount);
        emit SharesMinted(to, amount);
    }
}
