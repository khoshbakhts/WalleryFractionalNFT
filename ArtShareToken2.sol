// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/access/Ownable.sol";

contract ArtShareToken is ERC20, Ownable {
    uint8 private constant _DECIMALS = 2;

    uint256 public immutable MAX_SUPPLY;

    address public vault;
    bool public vaultSet;

    event VaultSet(address indexed vault);
    event SharesMinted(address indexed to, uint256 amount);

    modifier onlyVault() {
        require(msg.sender == vault, "ArtShareToken: caller is not vault");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(maxSupply_ > 0, "ArtShareToken: zero max supply");
        MAX_SUPPLY = maxSupply_;
    }

    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    function setVault(address _vault) external onlyOwner {
        require(!vaultSet, "ArtShareToken: vault already set");
        require(_vault != address(0), "ArtShareToken: zero address");
        vault = _vault;
        vaultSet = true;
        emit VaultSet(_vault);
    }

    function mintTo(address to, uint256 amount) external onlyVault {
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "ArtShareToken: exceeds max supply"
        );
        _mint(to, amount);
        emit SharesMinted(to, amount);
    }
}
