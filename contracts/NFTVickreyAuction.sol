//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./lib/TFHE.sol";
import "./lib/Gateway.sol";
import "./EncryptedERC20.sol";

contract NFTVickreyAuction is IERC721Receiver {
    error ZeroAddress();
    error StartAtLessThanNow();
    error EndAtLessThanStartAt();
    error AuctionActive();
    error AuctionNotActive();
    error OutsideBiddingWindow();
    error AuctionNotEnded();
    error NotAuctionWinner();
    error NoBidsToWithdraw();

    struct Auction {
        address seller;
        address highestBidder;
        address secondHighestBidder;
        EncryptedERC20 erc20Token;
        euint64 highestBid; // Encrypted highest bid
        euint64 secondHighestBid; // Encrypted second-highest bid
        uint128 startAt;
        uint128 endAt;
        uint8 status;
    }

    enum Status {
        NOT_ACTIVE,
        ACTIVE,
        FINISHED
    }

    mapping(address => mapping(uint256 => Auction)) public auctionInfo;
    mapping(address => mapping(EncryptedERC20 => euint64)) public userBids; // Encrypted user bids

    event AuctionCreated(
        uint256 indexed nftId,
        address indexed nftContract,
        address seller,
        uint128 startAt,
        uint128 endAt
    );

    event BidPlaced(
        uint256 indexed nftId,
        address indexed nftContract,
        address bidder
    );

    event AuctionFinished(
        uint256 indexed nftId,
        address indexed nftContract,
        address winner,
        uint256 finalPrice
    );

    event NFTWithdraw(
        uint256 indexed nftId,
        address indexed nftContract,
        address to
    );

    event BidWithdrawn(address indexed bidder);

    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        Auction storage auction = auctionInfo[msg.sender][tokenId];
        auction.seller = from;
        return this.onERC721Received.selector;
    }

    /**
     * @notice Creates a new NFT Vickrey auction.
     *
     * @param nftId The unique identifier of the NFT being listed.
     * @param nftContract The address of the contract of the NFT being listed.
     * @param erc20Token The ERC20 token to be used for bidding in the auction.
     * @param startAt The timestamp at which the auction will start.
     * @param endAt The timestamp at which the auction will end.
     */
    function listOnAuction(
        uint256 nftId,
        address nftContract,
        EncryptedERC20 erc20Token,
        uint128 startAt,
        uint128 endAt
    ) external {
        if (nftContract == address(0)) {
            revert ZeroAddress();
        }
        if (startAt <= block.timestamp) {
            revert StartAtLessThanNow();
        }
        if (endAt <= startAt) {
            revert EndAtLessThanStartAt();
        }

        Auction storage auction = auctionInfo[nftContract][nftId];
        if (auction.status != uint8(Status.NOT_ACTIVE)) {
            revert AuctionActive();
        }

        auction.seller = msg.sender;
        auction.erc20Token = erc20Token;
        auction.startAt = startAt;
        auction.endAt = endAt;
        auction.status = uint8(Status.ACTIVE);

        emit AuctionCreated(nftId, nftContract, msg.sender, startAt, endAt);
    }

    /**
     * @notice Places a bid on an active NFT Vickrey auction.
     *
     * @param nftId The unique identifier of the NFT being bid on.
     * @param nftContract The address of the contract of the NFT being bid on.
     * @param encryptedBid The encrypted bid amount.
     * @param inputProof The proof for the encrypted bid.
     */
    function placeBid(
        uint256 nftId,
        address nftContract,
        einput encryptedBid, // Encrypted bid input
        bytes calldata inputProof
    ) external {
        Auction storage auction = auctionInfo[nftContract][nftId];

        if (auction.status != uint8(Status.ACTIVE)) {
            revert AuctionNotActive();
        }
        if (
            block.timestamp < auction.startAt || block.timestamp > auction.endAt
        ) revert OutsideBiddingWindow();

        euint64 bidAmount = TFHE.asEuint64(encryptedBid, inputProof);

        // Transfer tokens securely
        TFHE.allowTransient(bidAmount, address(this));
        auction.erc20Token.transferFrom(msg.sender, address(this), bidAmount);

        // Track user bid amount securely
        userBids[msg.sender][auction.erc20Token] = TFHE.add(
            userBids[msg.sender][auction.erc20Token],
            bidAmount
        );

        // Update auction highest/second-highest bid
        ebool isHigher = TFHE.gt(bidAmount, auction.highestBid);
        auction.secondHighestBid = TFHE.select(
            isHigher,
            auction.highestBid,
            TFHE.max(auction.secondHighestBid, bidAmount)
        );
        auction.highestBid = TFHE.select(
            isHigher,
            bidAmount,
            auction.highestBid
        );
        auction.highestBidder = ebool.unwrap(isHigher) != 0
            ? msg.sender
            : auction.highestBidder;
        emit BidPlaced(nftId, nftContract, msg.sender);
    }

    /**
     * @notice Finalizes an NFT Vickrey auction.
     * If the auction has ended, the highest bidder wins the NFT and the second-highest bid is paid to the seller.
     * If no bids were placed, the NFT is returned to the seller.
     *
     * @param nftId The unique identifier of the NFT being auctioned.
     * @param nftContract The address of the contract of the NFT being auctioned.
     */
    function finalizeAuction(uint256 nftId, address nftContract) external {
        Auction storage auction = auctionInfo[nftContract][nftId];
        if (block.timestamp <= auction.endAt) {
            revert AuctionNotEnded();
        }
        if (auction.status != uint8(Status.ACTIVE)) {
            revert AuctionNotActive();
        }

        auction.status = uint8(Status.FINISHED);

        if (auction.highestBidder != address(0)) {
            // Transfer tokens to seller
            TFHE.allowTransient(
                auction.highestBid,
                address(auction.erc20Token)
            );
            auction.erc20Token.transfer(
                auction.seller,
                auction.secondHighestBid
            );
            
            euint64 refund = TFHE.sub(
                userBids[auction.highestBidder][auction.erc20Token],
                auction.highestBid
            );
            // Refund remaining tokens to highest bidder
            userBids[auction.highestBidder][auction.erc20Token] = refund;
        } else {
            // Return NFT if no bids placed
            IERC721(nftContract).safeTransferFrom(
                address(this),
                auction.seller,
                nftId
            );
        }
    }

    /**
     * @notice Withdraws a bid from an NFT Vickrey auction.
     * If the auction has ended, the bid amount is returned to the bidder.
     *
     * @param nftId The unique identifier of the NFT being auctioned.
     * @param nftContract The address of the contract of the NFT being auctioned.
     */
    function withdrawBid(uint256 nftId, address nftContract) external {
        Auction storage auction = auctionInfo[nftContract][nftId];
        if (auction.status != uint8(Status.FINISHED)) {
            revert AuctionNotEnded();
        }

        euint64 encryptedBidAmount = userBids[msg.sender][auction.erc20Token];
        if (ebool.unwrap(TFHE.eq(encryptedBidAmount, TFHE.asEuint64(0))) != 0) {
            revert NoBidsToWithdraw();
        }
        if (msg.sender == auction.highestBidder) {
            revert NotAuctionWinner();
        }

        userBids[msg.sender][auction.erc20Token] = TFHE.asEuint64(0); // Reset bid amount
        // Transfer tokens securely
        TFHE.allowTransient(encryptedBidAmount, msg.sender);
        auction.erc20Token.transfer(msg.sender, encryptedBidAmount);

        emit BidWithdrawn(msg.sender);
    }

    /**
     * @notice Withdraws an NFT from an NFT Vickrey auction.
     * If the auction has ended, the NFT is returned to the highest bidder.
     *
     * @param nftId The unique identifier of the NFT being auctioned.
     * @param nftContract The address of the contract of the NFT being auctioned.
     */
    function withdrawNFT(uint256 nftId, address nftContract) external {
        Auction storage auction = auctionInfo[nftContract][nftId];
        if (auction.highestBidder != msg.sender) {
            revert NotAuctionWinner();
        }
        if (auction.status != uint8(Status.FINISHED)) {
            revert AuctionNotEnded();
        }

        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, nftId);

        emit NFTWithdraw(nftId, nftContract, msg.sender);
    }
}
