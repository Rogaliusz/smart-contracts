// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./nfts.sol";

contract FlamingoCoinStaking is Ownable {
    struct StakedNFT {
        uint256 stakingFrom;
        address owner;
        uint256 tokenId;
    }

    struct CurrentReward {
        uint256 tokenId;
        uint256 value;
        uint256 nextRewardTime;
    }

    struct Stats {
        uint256 stakedHoldersCount;
        uint256 stakedNftsCount;
    }

    mapping(uint256 => StakedNFT) public stakedNfts;
    mapping(address => uint256[]) public ownerStakes;
    address[] private owners;

    uint256 private stakingInterval;
    uint256 private stakingReward;
    IERC20 private tokens;
    NFT private nfts;

    bool public paused = false;

    // stakingInterval - 1 day - 86400
    // Reward - 1 coin - 1000000000000000000
    constructor(
        address _nft,
        address _erc20,
        uint256 _stakingInterval,
        uint256 _stakingReward) {
        nfts = NFT(_nft);
        tokens = IERC20(_erc20);
        stakingInterval = 1 days;
        stakingReward = 1 ether;
    }

    function stake(uint256[] memory _tokenIds) public {
        require(!paused, "Contract paused");
        require(nfts.isApprovedForAll(msg.sender, address(this)));

        for(uint256 i=0; i<_tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            require(nfts.ownerOf(tokenId) == msg.sender, "You must own that nft");

            if (ownerStakes[msg.sender].length == 0) {
                owners.push(msg.sender);
            }

            StakedNFT memory staked = StakedNFT(block.timestamp, msg.sender, tokenId);
            stakedNfts[tokenId] = staked;
            ownerStakes[msg.sender].push(tokenId);

            nfts.transferFrom(msg.sender, address(this), tokenId);
        }
    }

    function unstake(uint256[] memory _tokenIds) public {
        uint256[] storage owned = ownerStakes[msg.sender];

        require(!paused, "Contract paused");
        require(owned.length != 0, "Fuck You scammer, You don't have any staked nfts");

        for (uint256 i=0; i < _tokenIds.length; i++ ) {
            uint256 tokenId = _tokenIds[i];
            require(nfts.ownerOf(tokenId) == address(this), "Nft must be staked");

            StakedNFT storage token = stakedNfts[tokenId];
            require(token.owner == msg.sender, "You must own that nft");

            // transfer
            nfts.transferFrom(address(this), msg.sender, tokenId);

            // cleanup
            delete stakedNfts[tokenId];

            for (uint256 j=0; j<owned.length; j++) {
                if (tokenId == owned[j]) {
                    owned[j] = owned[owned.length - 1];
                    owned.pop();

                    break;
                }
            }
        }

        // Clear history after last unstake
        if (owned.length == 0) {
            delete ownerStakes[msg.sender];

            for (uint256 i=0; i<owners.length; i++) {
                if (msg.sender == owners[i]) {
                    owners[i] = owners[owners.length - 1];
                    owners.pop();

                    break;
                }
            }
        }
    }

    function collect(uint256[] memory _tokenIds) public {
        uint256[] memory owned = ownerStakes[msg.sender];

        require(!paused, "Contract paused");
        require(owned.length != 0, "Fuck You scammer, You don't have any staked nfts");

        CurrentReward[] memory rewards = calculateRewards(_tokenIds);
        uint256 reward = 0;

        for (uint256 i=0; i<rewards.length; i++) {
            StakedNFT storage nft = stakedNfts[rewards[i].tokenId];

            require (nft.owner == msg.sender, "You must be owner of this nft");

            if (rewards[i].value == 0) {
                continue;
            }

            reward = reward + rewards[i].value;

            nft.stakingFrom = block.timestamp - (stakingInterval - rewards[i].nextRewardTime);
        }

        require(0 < reward, "Reward must greather than 0, You don't have rewards to collect");

        uint256 balance = tokens.balanceOf(address(this));

        require(balance > reward, "Ups, contract has not enought founds");
        require(tokens.transfer(msg.sender, reward), "Something goes wrong with transaction");
    }

    // View
    function calculateAllOwnedNFTsRewards() public view returns (CurrentReward[] memory) {
        require(!paused, "Contract paused");

        CurrentReward[] memory stakes;
        if (ownerStakes[msg.sender].length == 0) {
            return stakes;
        }

        return calculateRewards(ownerStakes[msg.sender]);
    }

    function calculateRewards(uint256[] memory _tokenIds) public view returns (CurrentReward[] memory) {
        require(!paused, "Contract paused");

        CurrentReward[] memory stakes = new CurrentReward[](_tokenIds.length);
        if (ownerStakes[msg.sender].length == 0) {
            return stakes;
        }

        for (uint256 i=0; i<_tokenIds.length; i++) {
            StakedNFT memory nft = stakedNfts[_tokenIds[i]];

            uint256 diff = block.timestamp - nft.stakingFrom;
            uint256 cycles = diff / stakingInterval;
            uint256 reward = stakingReward * cycles;
            uint256 toNextRewardSeconds = stakingInterval - (diff - stakingInterval * cycles);

            CurrentReward memory currentReward = CurrentReward(nft.tokenId, reward, toNextRewardSeconds);
            stakes[i] = currentReward;
        }

        return stakes;
    }

    function getStakingInterval() public view returns (uint256) {
        return stakingInterval;
    }

    function getStakingReward() public view returns (uint256) {
        return stakingReward;
    }

    function getStats() public view returns (Stats memory) {
        return Stats(owners.length, nfts.balanceOf(address(this)));
    }

    // owner
    function setStakingInterval(uint256 _stakingInterval) external onlyOwner {
        stakingInterval = _stakingInterval;
    }

    function setStakingReward(uint256 _stakingReward) external onlyOwner {
        stakingReward = _stakingReward;
    }

    function pause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function getOwners() external view onlyOwner returns (address[] memory) {
        return owners;
    }

    // in case when contract will have a bug on production
    function returnNftsToOwners() external onlyOwner {
        for (uint i=0; i < owners.length; i++) {
            for (uint tokenIdx=0; tokenIdx < ownerStakes[owners[i]].length; tokenIdx++) {
                uint256 tokenId = ownerStakes[owners[i]][tokenIdx];
                nfts.transferFrom(address(this), stakedNfts[tokenId].owner, tokenId);
                delete stakedNfts[tokenIdx];
            }

            delete ownerStakes[owners[i]];
        }

        delete owners;
    }
}
