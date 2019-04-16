pragma solidity >=0.5.0 <0.6.0;

import "./utils/Initializable.sol";
import "./utils/SafeMath.sol";
import "./XyStakingConsensus.sol";
import "./IXyRequester.sol";
import "./token/ERC20/SafeERC20.sol";

// We should be bringing in responses from the staking consensus contract

 /**
    @title XyReward
    @dev Manages and pays out the reward for succcessful answer of a staked request
  */

contract XyReward is Initializable, IXyRequester {
    using SafeMath for uint;

    XyStakingConsensus public scsc;
    address public xyoToken;

    event IntersectResponse(bytes32 requestId, uint weiPayment, uint xyoPayment, address payable beneficiary, bool didIntersect);
    event NewPayOnDeliveryRequest(bytes32 requestId, address requester, uint weiPayment, uint xyoPayment, address payable beneficiary);

    mapping (bytes32 => bool) public didIntersect;
    mapping (bytes32 => uint) public requestIndex;
    IPFSRequest[] public requests;

    function initialize (
        address stakingConsensus, 
        address _xyoToken
    )
        initializer public
    {
        scsc = XyStakingConsensus(stakingConsensus);
        xyoToken = _xyoToken;
    }

    /**
      @dev Called by diviner.  API for client to request an intersection question
      @param requestId - the hash of the request (first 2 bytes stripped)
      @param xyoBounty - the xyo bounty for the request (approve scsc for this amount)
      @param xyoReward - the amount of XYO to pay on correct response
      @param weiReward - the amount of eth to pay on correct response
      @param beneficiary The destination address of the funds.
    */

    // function requestReward (
    //     bytes32 requestId, 
    //     uint xyoBounty, 
    //     uint xyoReward,
    //     uint weiReward, 
    //     address payable beneficiary
    // )
    //   public 
    //   payable
    // {

    // }

// This should also check the supporting data from the responses in the intersection block 
    /** 
      Will refund the asker prior to deleting the request
      @param requestId - the requestId,
      @param responseFromBlock
      @param payee - who to pay
    */
    function reward(bytes32 requestId, address payable payee, uint xyoBounty) public {       
        // stakingBlock and response data here?  This does not account for off-chain storage of request ids...yet 
        
        /** 
          bytes32 supportingData = XyStakingConsensus.supportingDataForRequest(requestId) 
          uint stakingBlock = XyStakingConsensus.blockForRequest(requestId).stakingBlock
          *** what would get responseData from the array?
          if (supportingData === responseData) {
           uint rewardId = XyStakingConsensus.withdrawRewardsRequest(xyoBounty) 
           emit RewardClaimed(requestId, rewardId, payee, xyoBounty);
           SafeERC20.transfer(xyoToken, payee, xyoBounty);
          }
         */
    }
}