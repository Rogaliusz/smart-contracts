/*
ERC-721A Smart contract
@DonFlamingo - https://linktr.ee/donflamingo

Features: 
- whitelist, 
- gas optimization,
- private sale,
- sale limits.
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721A.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract EtherRoyal is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;

    string private baseURI;
    bool public paused = false;
    uint256 public maxSupply = 8888;
    uint256 public price = 0.069 ether;
    
    mapping (address => uint256) public saleMintCount;
    uint256 public saleWalletLimit = 10;
    bool public saleStarted = false;

    mapping (address => uint256) public presaleMintCount;
    uint256 public presaleWalletLimit = 3;
    bool public presaleStarted = false;
    bytes32 public presaleMerkleRoot;

    event saleModeChanged();

    constructor(string memory _tokenUrl) ERC721A ("Sample Name", "SN"){
        baseURI = _tokenUrl;
    }

    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    
    modifier correctPayment(uint8 quantity) {
        require(quantity * price == msg.value);
        _;
    }

    modifier supplyLimit(uint8 quantity) {
        require(totalSupply() + quantity <= maxSupply, "No more tokens");
        _;
    }

    modifier presale(uint8 quantity) {
        require(presaleStarted, "Presale must be started");
        require(presaleMintCount[msg.sender] + quantity <= presaleWalletLimit, "Wallet limit reached");
        _;
    }

    modifier sale(uint8 quantity) {
        require(saleStarted, "Sale must be started");
        require(saleMintCount[msg.sender] + quantity <= saleWalletLimit, "wallet limit reached");
        _;
    }

    modifier isValidMerkleProof(bytes32[] calldata merkleProof) {
        require(
            MerkleProof.verify(
                merkleProof,
                presaleMerkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "Address does not exist in list"
        );
        _;
    }

    function saleMint(uint8 quantity) external payable notPaused nonReentrant supplyLimit(quantity) sale(quantity) {
        _safeMint(msg.sender, quantity);
        saleMintCount[msg.sender] += quantity;
    }

    function presaleMint(uint8 quantity, bytes32[] calldata merkleProof) external payable notPaused nonReentrant supplyLimit(quantity) isValidMerkleProof(merkleProof) presale(quantity)  {
        _safeMint(msg.sender, quantity);
        presaleMintCount[msg.sender] += quantity;
    }

    function ownerMint(uint8 quantity, address toAddress) external supplyLimit(quantity) onlyOwner {
        _safeMint(toAddress, quantity);
    } 

    function startPresale() external onlyOwner {
        presaleStarted = true;
        saleStarted = false;

        emit saleModeChanged();
    }

    function startSale() external onlyOwner {
        presaleStarted = false;
        saleStarted = true;

        emit saleModeChanged();
    }

    function resetSale() external onlyOwner {
        presaleStarted = false;
        saleStarted = false;

        emit saleModeChanged();
    }

    function setPause(bool pause) external onlyOwner {
        paused = pause;
    }

    function updatePrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setPresaleLimit(uint8 _presaleLimit) external onlyOwner {
        presaleWalletLimit = _presaleLimit;
    }

    function setSaleLimit(uint8 _saleLimit) external onlyOwner {
        saleWalletLimit = _saleLimit;
    }

    function setPresaleListMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        presaleMerkleRoot = merkleRoot;
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function withdraw() public onlyOwner {
        uint256 donflamingoFee = address(this).balance * 5 / 100;
        (bool giveMe5PercentageFee, ) = payable(0xdCd6B7449167220724084bfD61f9B205c7dfa5a1).call{value: donflamingov}("");
        require(giveMe5PercentageFee);

        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }

    function _startTokenId() internal view override virtual returns (uint256) {
        return 1;
    }

    function getBaseURI() external view returns (string memory) {
        return baseURI;
    }

    function leftLimit() external view returns (uint256) {
        require(presaleStarted || saleStarted, "Sales wasn't started yet");

        if (presaleStarted) {
            return presaleWalletLimit - presaleMintCount[msg.sender];
        }
        if (saleStarted) {
            return saleWalletLimit - saleMintCount[msg.sender];
        }

        return 0;
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        uint256 currentTokenId = 1;
        uint256 ownedTokenIndex = 0;

        while (ownedTokenIndex < ownerTokenCount && currentTokenId <= maxSupply) {
            address currentTokenOwner = ownerOf(currentTokenId);

            if (currentTokenOwner == _owner) {
                ownedTokenIds[ownedTokenIndex] = currentTokenId;
                ownedTokenIndex++;
            }

            currentTokenId++;
        }

        return ownedTokenIds;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Nonexistent token");

        return
            string(abi.encodePacked(baseURI, "/", tokenId.toString(), ".json"));
    }
}