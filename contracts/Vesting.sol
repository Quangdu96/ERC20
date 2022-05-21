// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract Vesting is Ownable {
    using SafeMath for uint8;
    using SafeMath for uint64;
    using SafeMath for uint256;

    struct Claimer {
        address addr;
        uint256 totalClaimableAmount;
        uint256 remainingClaimableAmount;
        uint8   claimedTimes;
        uint64  lastClaimTime;
    }

    ERC20   public  _tokenContract;
    bool    public  _isOpenedForClaim;
    uint8   public  _firstReleasePercentage;
    uint64  public  _delayAfterFirstRelease;
    uint8   public  _numberOfPeriodicClaim;
    uint8   public  _periodicClaimPercentage;
    uint64  public  _periodicClaimDuration;
    uint256 public  _minimumTotalClaimableAmount;
    mapping(address => Claimer) private _claimerList;
    
    modifier onlyWhenOpenedForClaim {
        require(_isOpenedForClaim, "Claim has not yet been opened or has been closed");
        _;
    }

    event OpenClaim(uint64 timestamp);
    event CloseClaim(uint64 timestamp);
    event AddClaimer(address indexed claimerAddress, uint256 claimableAmount);

    /**
     * @param claimerAddress claimer's address
     * @param claimedTimes number of times the claimer has claimed including this claim (equals 1 at first claim (release), 2 at second claim,..)
     * @param amount amount of token of this claim
     * @param timestamp timestamp of this claim, as seconds since unix epoch
     */
    event Claim(address indexed claimerAddress, uint8 indexed claimedTimes, uint256 amount, uint64 timestamp);

    /**
     * @dev constructor
     * @param tokenAddress_ address of deployed token contract
     * @param firstReleasePercentage_ percentage from which calculate the amount of tokens claimer receives in first claim (release), 1 = 1%
     * @param delayAfterFirstRelease_ time duration the claimer must wait since first claim (release) to claim the second time
     * @param numberOfPeriodicClaim_ number of claim the claimer must do AFTER THE FIRST CLAIM (RELEASE) to receive total claimable tokens.
     * The claimer will receive all claimable tokens after (numberOfPeriodicClaim + 1) claims
     * @param periodicClaimDuration_ time duration the claimer must wait between periodic claims
     */
    constructor(address tokenAddress_,
            uint8 firstReleasePercentage_,
            uint64 delayAfterFirstRelease_,
            uint8 numberOfPeriodicClaim_,
            uint64 periodicClaimDuration_) {
        _tokenContract = ERC20(tokenAddress_);
        _isOpenedForClaim = false;
        _firstReleasePercentage = firstReleasePercentage_;
        _delayAfterFirstRelease = delayAfterFirstRelease_;
        _numberOfPeriodicClaim = numberOfPeriodicClaim_;
        _periodicClaimPercentage = SafeCast.toUint8(SafeMath.sub(100, _firstReleasePercentage)
                                                            .div(_numberOfPeriodicClaim));
        _periodicClaimDuration = periodicClaimDuration_;

        /**
         * @dev If total claimable amount of a specific claimer were smaller than _minimumTotalClaimableAmount,
         * either the first claim (release) amount or periodic claim amount of that claimer might be 0 (due to integer division).
         * This vesting contract doesn't allow those 2 amounts to be 0 at the moment.
         */
        _minimumTotalClaimableAmount =
            SafeMath.div(100, _firstReleasePercentage <= _periodicClaimPercentage ? _firstReleasePercentage : _periodicClaimPercentage)
                    .add(1);
    }

    function openClaim() public onlyOwner {
        _isOpenedForClaim = true;
        emit OpenClaim(SafeCast.toUint64(block.timestamp));
    }

    function closeClaim() public onlyOwner {
        _isOpenedForClaim = false;
        emit CloseClaim(SafeCast.toUint64(block.timestamp));
    }

    /**
     * @dev Nhắn anh Hùng: em cảm thấy hàm fundVest k cần, tại token owner có thể gọi transfer để chuyển token trực tiếp cho Vesting contract,
     * phải approve rồi tranferFrom mất công hơn k cần thiết
     */
    function fundVest(uint256 amount) external onlyOwner {
        _tokenContract.transferFrom(msg.sender, address(this), amount);
    }

    function addClaimer(address claimerAddress, uint256 claimableAmount) external onlyOwner {
        require(_claimerList[claimerAddress].totalClaimableAmount == 0, "Claimer already exists");

        string memory errorMessage = string(bytes.concat("Claimable amount must be at least ",
                                                        abi.encodePacked(_minimumTotalClaimableAmount),
                                                        " ",
                                                        bytes(_tokenContract.symbol()) ));  // Just string concatenate
        require(claimableAmount >= _minimumTotalClaimableAmount, errorMessage);

        Claimer memory claimer = Claimer(claimerAddress, claimableAmount, claimableAmount, 0, 0);
        _claimerList[claimerAddress] = claimer;
        emit AddClaimer(claimerAddress, claimableAmount);
    }

    function claim() external onlyWhenOpenedForClaim {
        Claimer storage claimer = _claimerList[msg.sender];
        require(claimer.totalClaimableAmount != 0, "Claimer not found");
        uint256 claimedAmount = 0;
        
        if (claimer.claimedTimes == 0) {
            claimedAmount = claimer.totalClaimableAmount.mul(_firstReleasePercentage).div(100);
        } else if (claimer.claimedTimes == 1) {
            require(block.timestamp.sub(claimer.lastClaimTime) >= _delayAfterFirstRelease, "Elapsed time is not enough since first release");
            claimedAmount = claimer.totalClaimableAmount.mul(_periodicClaimPercentage).div(100);
        } else if (claimer.claimedTimes > 1 && claimer.claimedTimes < _numberOfPeriodicClaim) {
            require(block.timestamp.sub(claimer.lastClaimTime) >= _periodicClaimDuration, "Elapsed time is not enough since last claim");
            claimedAmount = claimer.totalClaimableAmount.mul(_periodicClaimPercentage).div(100);
        } else if (claimer.claimedTimes == _numberOfPeriodicClaim) {
            require(block.timestamp.sub(claimer.lastClaimTime) >= _periodicClaimDuration, "Elapsed time is not enough since last claim");
            claimedAmount = claimer.remainingClaimableAmount;
        } else
            revert("Claimer has claimed all tokens");

        claimer.remainingClaimableAmount -= claimedAmount;
        claimer.claimedTimes++;
        claimer.lastClaimTime = SafeCast.toUint64(block.timestamp);
        _tokenContract.transfer(claimer.addr, claimedAmount);
        emit Claim(claimer.addr, claimer.claimedTimes, claimedAmount, claimer.lastClaimTime);
    }
}
