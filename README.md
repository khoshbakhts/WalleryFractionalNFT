# 🖼️ Wallery Fractionalized NFT System

**Version 1.0 — Minimal, Production-Ready Architecture**

A clean, modular smart contract suite for **fractionalizing artworks as NFTs** within the **Wallery** ecosystem.  
It enables NFT minting, vault-based fractionalization (ERC-721 + ERC-20), on-chain buyout voting, and ETH distribution to fractional owners.

---

## ⚙️ Overview

| Contract | Purpose | File |
|-----------|----------|------|
| **WalleryArtworkNFT** | ERC-721 NFT contract with metadata and royalty support | `WalleryArtworkNFT.sol` |
| **ArtShareToken (v1.1)** | ERC-20 fractional share token, with vault-controlled burn | `ArtShareToken.sol` |
| **GalleryVault** | Holds a specific NFT, mints share tokens, manages buyout and claim | `GalleryVault.sol` |
| **GalleryVaultFactory** | Deploys and registers new vaults for each NFT | `GalleryVaultFactory.sol` |
| **GalleryBuyoutManager** | Manages buyout proposals and voting using locked share tokens | `GalleryBuyoutManager.sol` |

All contracts are **Solidity ^0.8.24** and compatible with **OpenZeppelin v5.x**.

---

## 🧩 Logical Architecture

WalleryArtworkNFT (ERC721)
↓ safeMint()
GalleryVaultFactory
↓ createVault()
GalleryVault
↓ deposit() / setBuyoutPrice()
GalleryBuyoutManager
↓ propose() / lock() / execute()
Vault claim() → ETH payout + burn shares


---

## 🚀 Deployment Steps (Remix or Hardhat)

### 1️⃣ Deploy `WalleryArtworkNFT`
```solidity
constructor(
  string name,                // e.g. "Wallery Gallery"
  string symbol,              // e.g. "WART"
  address royaltyReceiver,    // optional
  uint96 royaltyFeeNumerator  // optional, e.g. 500 = 5%
)

Call safeMint(to, tokenURI) to mint an artwork NFT.
Example: ipfs://QmExampleMetadataHash → tokenId = 1.

Create a Vault via GalleryVaultFactory

Deploy GalleryVaultFactory(owner)
Then call:

createVault(
  owner_,         // gallery admin
  artwork,        // NFT contract address
  tokenId,        // e.g. 1
  shareName,      // "Mona Lisa Shares"
  shareSymbol,    // "MLS"
  shareDecimals,  // e.g. 18
  totalShares,    // e.g. 1_000_000 * 10^18
  initialHolder   // initial token recipient
)


→ returns the address of the newly deployed GalleryVault.

3️⃣ Deposit NFT into Vault

On the NFT contract → approve(vault, tokenId)

On the Vault → deposit()

The NFT is now safely held (locked) inside the vault.

4️⃣ Set Buyout Price & Initiate Buyout

On Vault:

setBuyoutPrice(5 ether);


On BuyoutManager:

propose(vault, durationSec) // with msg.value = 5 ether


Then shareholders:

Approve the BuyoutManager to spend shares
ArtShareToken.approve(BuyoutManager, amount)

Lock shares as buyout votes
lock(proposalId, amount)

When locked ≥ 51% (default quorum), call execute(proposalId)

→ Manager executes vault.buyout{value:price}(), transferring the NFT and storing ETH inside the vault.

5️⃣ Claim ETH After Buyout

Each shareholder:

approve(vault, amount);
vault.claim(amount);


The Vault burns the shares and sends proportional ETH to the claimer.

Formula:𝑝𝑎𝑦𝑜𝑢𝑡=𝑝𝑟𝑜𝑐𝑒𝑒𝑑𝑠𝑊𝑒𝑖×(𝑎𝑚𝑜𝑢𝑛𝑡/𝑡𝑜𝑡𝑎𝑙𝑆ℎ𝑎𝑟𝑒𝑠𝐴𝑡𝑆𝑎𝑙𝑒)
payout=proceedsWei×(amount/totalSharesAtSale)

🔐 Security & Design Highlights

ReentrancyGuard for ETH transfers

NFT transfers via safeTransferFrom

Vault-controlled burning (burnFromVault) ensures integrity

Buyout only executes if msg.value == buyoutPriceWei

Full traceability: every Vault and Proposal is registered on-chain

🧱 File Structure
contracts/
 ├─ WalleryArtworkNFT.sol
 ├─ ArtShareToken.sol
 ├─ GalleryVault.sol
 ├─ GalleryVaultFactory.sol
 └─ GalleryBuyoutManager.sol

