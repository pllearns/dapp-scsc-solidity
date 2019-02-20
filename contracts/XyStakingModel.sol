pragma solidity >=0.5.0 <0.6.0;

import "./XyStakableToken.sol";
import "./token/ERC20/IERC20.sol";
import "./token/ERC20/SafeERC20.sol";
import "./XyGovernance.sol";
import "./utils/SafeMath.sol";

contract XyStakingModel {
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    // IERC20 contract for stake denomination
    IERC20 public xyoToken;

    // 721 contract that we reference for all things staked
    XyStakableToken stakableToken;

    XyGovernance public params;

    // Number of cooldown blocks to allow time to challenge staked false answers
    uint public stakeCooldown;
    uint public unstakeCooldown;


    // Track the total active stake in XYO
    uint public totalActiveStake;

    // escrow the penalty stake
    uint public penaltyStake;

    // Stake data associated with all staking tokens
    struct Stake {
        uint amount;
        uint stakeBlock;
        uint unstakeBlock;
        uint stakee; 
        address staker;
        bool isActivated;
    }

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier whenActive() {
        require(params.get("xyPaused") == 0, "Staking is Paused");
        _;
    }

    // Mapping from staking model id to stake metadata     
    mapping (uint => Stake) public stakeData;

    // The staking token ids associated with stakable tokens
    mapping (uint => uint[]) public stakeeToStakingIds;
    mapping (address => uint[]) public stakerToStakingIds;

    // holds staking id to index in the stakeeToStakingIds array
    mapping (uint => uint) public stakingStakeeIndex;
    mapping (uint => uint) public stakingStakerIndex;

    
    /** EVENTS */
    event Staked(
        address indexed staker,
        uint indexed stakingId,
        uint indexed stakee,
        uint amount
    );

    event ActivatedStake(
        address indexed staker,
        uint indexed stakingId,
        uint indexed stakee,
        uint amount
    );

    event Unstaked(
        address indexed staker,
        uint indexed stakingId,
        uint indexed stakee,
        uint amount
    );

    event Withdrawl(
        address indexed staker,
        uint amount
    );

    // Total/Active amounts staked by stakee and staker 
    struct StakeAmounts {
        uint totalStake;
        uint activeStake;
        uint totalUnstake;
    }

    mapping (uint => StakeAmounts) public stakeeStake;
    mapping (address => StakeAmounts) public stakerStake;

    /** Creates a Staking token contract 
        @param _token - The ERC20 token to stake with 
        @param _stakableToken - The ERC721 token to place stakes on 
        @param _governanceContract - The contract that governs the params and actions of the system
    */
    constructor (
        address _token,
        address _stakableToken,
        address _governanceContract
    )
        public
    {
        xyoToken = IERC20(_token);
        stakableToken = XyStakableToken(_stakableToken);
        params = XyGovernance(_governanceContract);
    }

    /** Increase and decrease cached stake amounts */
    function updateCacheOnStake(uint amount, uint stakee) internal {
        stakeeStake[stakee].totalStake = stakeeStake[stakee].totalStake.add(amount);
        stakerStake[msg.sender].totalStake = stakerStake[msg.sender].totalStake.add(amount);
    }
    function updateCacheOnActivate(uint amount, uint stakee) internal {
        stakeeStake[stakee].activeStake = stakeeStake[stakee].activeStake.add(amount);
        stakerStake[msg.sender].activeStake = stakerStake[msg.sender].activeStake.add(amount);
        totalActiveStake = totalActiveStake.add(amount);
    }
    function updateCacheOnUnstake(Stake memory data) internal {
        reduceStake(data, data.amount);
        stakeeStake[data.stakee].totalUnstake = stakeeStake[data.stakee].totalUnstake.add(data.amount);
        stakerStake[data.staker].totalUnstake = stakerStake[data.staker].totalUnstake.add(data.amount);
    }
    function updateCacheOnWithdraw(uint amount, uint stakee) internal {
        stakeeStake[stakee].totalUnstake = stakeeStake[stakee].totalUnstake.sub(amount);
        stakerStake[msg.sender].totalUnstake = stakerStake[msg.sender].totalUnstake.sub(amount);
    }

    function reduceStake(Stake memory data, uint quantity) internal {
        stakeeStake[data.stakee].totalStake = stakeeStake[data.stakee].totalStake.sub(quantity);
        stakerStake[data.staker].totalStake = stakerStake[data.staker].totalStake.sub(quantity);
        if (data.isActivated) {
            stakeeStake[data.stakee].activeStake = stakeeStake[data.stakee].activeStake.sub(quantity);
            stakerStake[data.staker].activeStake = stakerStake[data.staker].activeStake.sub(quantity);
            totalActiveStake = totalActiveStake.sub(quantity);
        }
    }

    function _unstakeGovernanceAction(uint stakee, uint startIndex, uint batchSize, uint penalty) private {
        for (uint i = startIndex; i < batchSize + startIndex; i++) {
            uint token = stakeeToStakingIds[stakee][i];
            Stake storage data = stakeData[token];
            if (data.unstakeBlock == 0) {
                if (penalty > 0) {
                    uint penaltyAmount = penalty.mul(data.amount).div(100);
                    reduceStake(data, penaltyAmount);
                    penaltyStake.add(penaltyAmount);
                }
                updateCacheOnUnstake(data);
                data.unstakeBlock = block.number;
            }
        }
    }

    function isUnstakeAction(XyGovernance.ActionType actionType) pure public returns (bool) {
        return (actionType == XyGovernance.ActionType.UNSTAKE  || actionType == XyGovernance.ActionType.EOL);
    }

    /** 
        Call this when it's time to resolve a passed governance action
        @param stakee the staked item receiving action
        @param startIndex if a batchable action, where to start
        @param batchSize if batchable action, batchSize
    */
    function resolveGovernanceAction(uint stakee, uint startIndex, uint batchSize) public {
        (,uint penalty,XyGovernance.ActionType actionType,bool accepted) = params.actions(stakee);
        require(accepted == true, "action must be accepted");
        // unstake action
        if (actionType == XyGovernance.ActionType.UNSTAKE) {
            _unstakeGovernanceAction(stakee, startIndex, batchSize, penalty);
        } else if (actionType == XyGovernance.ActionType.EOL) {
            // unstake all with no penalty
            _unstakeGovernanceAction(stakee, startIndex, batchSize, 0);
            // burn stakee 721
            stakableToken.burn(stakee);
        } else if (actionType == XyGovernance.ActionType.ADD_BP) {
            stakableToken.enableBlockProducer(stakee, true);
            params.resolveAction(stakee);
        } else if (actionType == XyGovernance.ActionType.REMOVE_BP) {
            stakableToken.enableBlockProducer(stakee, false);
            params.resolveAction(stakee);
        } 

        if (isUnstakeAction(actionType) && stakeeStake[stakee].activeStake == 0) {
            params.resolveAction(stakee);
        }
    }

    /** 
        Adds stake to a stakable token id
        @dev This contract must be approved to transfer tokens by token holder
        @param stakee - the stakable token to stake
        @param amount - the amount to stake
    */
    function stake(uint stakee, uint amount)
        whenActive 
        public
        returns (uint)
    {
        require(params.hasUnresolvedAction(stakee) == false, "All actions on stakee must be resolved");
        require(stakableToken.exists(stakee) == true, "Stakable token must exist");
        updateCacheOnStake(amount, stakee);

        // random generated token id
        uint newToken = uint(keccak256(abi.encodePacked(stakee, msg.sender, block.number)));
        Stake memory data = Stake(
            amount,         // amount
            block.number,   // stakeBlock
            0,              // unstakeBlock
            stakee,         // stakee 
            msg.sender,
            false           // isActivated
        );

        // Store the staking data
        stakingStakeeIndex[newToken] = stakeeToStakingIds[stakee].length;
        stakeeToStakingIds[stakee].push(newToken);
        stakingStakerIndex[newToken] = stakerToStakingIds[msg.sender].length;
        stakerToStakingIds[msg.sender].push(newToken);
        stakeData[newToken] = data;

        // Escrow the ERC20
        xyoToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, newToken, stakee, amount);
        return newToken;
    }
    
    /**
        @dev Activate a stake that is past challenge period within XYO
        @param stakingId - the tokenId of the staking token
     */
    function activateStake(uint stakingId) 
        whenActive
        public 
    {
        Stake storage data = stakeData[stakingId];
        require(data.staker == msg.sender, "Only the staker can activate");
        require(data.isActivated == false, "cannot re-activate stake");
        data.isActivated = true;
        require(data.stakeBlock + params.get("xyStakeCooldown") < block.number, "Not ready to activate stake yet");
        updateCacheOnActivate(data.amount, data.stakee);
        emit ActivatedStake(msg.sender, stakingId, data.stakee, data.amount);
    }

    /** 
        unstake a specific previous stake 
        @param stakingId - the tokenId of the staking token
    */
    function unstake(uint stakingId)
        whenActive
        public
    {
        Stake storage data = stakeData[stakingId];
        require(data.staker == msg.sender, "Only the staker can unstake a stake");
        require(data.stakeBlock + params.get("xyStakeCooldown") < block.number, "Staking needs to cooldown");
        require(data.unstakeBlock == 0, "Cannot re-unstake");
        updateCacheOnUnstake(data);
        data.isActivated = false;
        data.unstakeBlock = block.number;
        emit Unstaked(data.staker, stakingId, data.stakee, data.amount);
    }

    /** 
        Internally used to remove token and adjust state array with no iterating 
        @param stakingId - the stakingId to remove
    */
    function removeStakeeData(uint stakingId) 
        internal 
    {
        uint stakee = stakeData[stakingId].stakee;

        uint stakeeIndex = stakingStakeeIndex[stakingId];

        uint lastStakeeIndex = stakeeToStakingIds[stakee].length - 1;
        uint lastStakeeId = stakeeToStakingIds[stakee][lastStakeeIndex];
            
        stakeeToStakingIds[stakee][stakeeIndex] = lastStakeeId;
        stakeeToStakingIds[stakee][lastStakeeIndex] = 0;

        stakeeToStakingIds[stakee].length--;
        delete stakingStakeeIndex[stakingId];
        stakingStakeeIndex[lastStakeeId] = stakeeIndex;
    }

       /** 
        Internally used to remove token and adjust state array with no iterating 
        @param stakingId - the stakingId to remove
    */
    function removeStakerData(uint stakingId) 
        internal 
    {
        address staker = stakeData[stakingId].staker;

        uint stakerIndex = stakingStakerIndex[stakingId];

        uint lastStakerIndex = stakerToStakingIds[staker].length - 1;
        uint lastStakerId = stakerToStakingIds[staker][lastStakerIndex];
            
        stakerToStakingIds[staker][stakerIndex] = lastStakerId;
        stakerToStakingIds[staker][lastStakerIndex] = 0;

        stakerToStakingIds[staker].length--;
        delete stakingStakerIndex[stakingId];
        stakingStakerIndex[lastStakerId] = stakerIndex;
    }

    /** 
        Withdraw a single token's stake by token id, removes staking token
        @param stakingId - the tokenId of the staking token to remove
    */
    function withdrawStake(uint stakingId)
      whenActive
      public 
    {
        Stake memory data = stakeData[stakingId];
        require(params.hasUnresolvedAction(data.stakee) == false, "All actions on stakee must be resolved");
        require(data.staker == msg.sender, "Only owner can withdraw");
        require (data.unstakeBlock > 0 && (data.unstakeBlock + params.get("xyUnstakeCooldown")) < block.number, "Not ready for withdraw");
        removeStakeeData(stakingId);
        removeStakerData(stakingId);
        updateCacheOnWithdraw(data.amount, data.stakee);
        xyoToken.safeTransfer(msg.sender, data.amount);
        emit Withdrawl(msg.sender, data.amount);
    }

    /** 
        Withdraw a batch of first avaliable staking tokens
        @param batchLimit - Allows iterating over withdrawing due to gas limits
        if batchlimit is 0, try withdrawing all available tokens (be prepared for out of gas if you've got > 50 tokens)
    */
    function withdrawManyStake(uint batchLimit)
        whenActive
        public
    {
        uint balance = numStakerStakes(msg.sender);
        uint limit = batchLimit > 0 ? batchLimit : balance;
        uint withdrawAmt = 0;
        uint[] memory removeArr = new uint[](limit);
        uint numremove = 0;
        for (uint i = 0; i < balance && i < limit; i++) {
            Stake memory data = stakeData[stakerToStakingIds[msg.sender][i]];

            if (data.unstakeBlock > 0 && (data.unstakeBlock + params.get("xyUnstakeCooldown")) < block.number && params.hasUnresolvedAction(data.stakee) == false) {
                removeArr[numremove] = stakerToStakingIds[msg.sender][i];      
                numremove++;
            }      
        }
        for (uint b = 0; b < numremove; b++) {
            removeStakeeData(removeArr[b]);
            removeStakerData(removeArr[b]);
            Stake memory data = stakeData[removeArr[b]];
            withdrawAmt += data.amount;
            updateCacheOnWithdraw(data.amount, data.stakee);
        }

        if (withdrawAmt > 0) {
            xyoToken.safeTransfer(msg.sender, withdrawAmt);
            emit Withdrawl(msg.sender, withdrawAmt);
        }
    }

    /** Get the available unstake, counting only stakes that can be withdrawn */    
    function getAvailableStakerUnstake(address staker)
        external
        view
        returns(uint)
    {
        uint stakeTotal = 0;
        uint num = numStakerStakes(staker);
        for (uint i = 0; i < num; i++) {
            Stake memory data = stakeData[stakerToStakingIds[staker][i]];
            if (data.unstakeBlock > 0 && (data.unstakeBlock + params.get("xyUnstakeCooldown")) < block.number) {
                stakeTotal += data.amount;
            }
        }
        return stakeTotal;
    }

    /** Get the available unstake, counting only stakes that can be withdrawn */    
    function getAvailableStakeeUnstake(uint stakee)
        external
        view
        returns(uint)
    {
        uint[] memory stakeList = stakeeToStakingIds[stakee];
        uint stakeTotal = 0;
        for (uint i = 0; i < stakeList.length; i++) {
            Stake memory data = stakeData[stakeList[i]];
            if (data.unstakeBlock > 0 && (data.unstakeBlock + params.get("xyUnstakeCooldown")) < block.number) {
                stakeTotal += data.amount;
            }
        }
        return stakeTotal;
    }

    /** Public getters */
    function numStakerStakes(address staker) public view returns (uint) {
        return stakerToStakingIds[staker].length;
    }
    function numStakeeStakes(uint stakee) public view returns (uint) {
        return stakeeToStakingIds[stakee].length;
    }
    function totalStakeAndUnstake(address staker) public view returns (uint) {
        return stakerStake[staker].totalUnstake + stakerStake[staker].totalStake;
    }
}