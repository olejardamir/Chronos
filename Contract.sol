pragma solidity 0.5 .11;

// A token that can be mined without any hardware or mining pools.
// In the near future as the computing progresses, the security of the networks will become near-perfect
// This means that the BTC mining will not be necessary, except for the ledger and the book-keeping purposes.
// Time would certainly become as valuable as the money, and therefore, time will become the most important asset to digital currencies.
// With this token, we are making a step forward, making it mineable without any need for hardware or mining pools.
// All you need is a connection to a network, and a minimal amount of Ethereum to make claims and to obtain the rewards.
// This is a represantion of a BTC model as it would function in the world with the perfect security and a total privacy across the networks.
//
// Some of the code has been copied from a 0xBTC project in order to speed up development by the code reuse.
//
// Symbol       : BTCHR
// Name         : Bitcoin Chronos
// Total supply : 21,000,000.00
// Decimals     : 8
// Author       : Damir Olejar, end of 2019.
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Safe maths
// ----------------------------------------------------------------------------

library SafeMath {
  function add(uint a, uint b) internal pure returns(uint c) {
    c = a + b;
    require(c >= a);
  }

  function sub(uint a, uint b) internal pure returns(uint c) {
    require(b <= a);
    c = a - b;
  }

  function mul(uint a, uint b) internal pure returns(uint c) {
    c = a * b;
    require(a == 0 || c / a == b);
  }

  function div(uint a, uint b) internal pure returns(uint c) {
    require(b > 0);
    c = a / b;
  }

}

library ExtendedMath {
  function min(uint a, uint b) internal pure returns(uint c) {
    if (a > b) return b;
    return a;
  }
}

// ----------------------------------------------------------------------------
// ERC Token Standard #20 Interface
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
// ----------------------------------------------------------------------------

contract ERC20Interface {

  function totalSupply() public view returns(uint);

  function balanceOf(address tokenOwner) public view returns(uint balance);

  function allowance(address tokenOwner, address spender) public view returns(uint remaining);

  function transfer(address to, uint tokens) public returns(bool success);

  function approve(address spender, uint tokens) public returns(bool success);

  function transferFrom(address from, address to, uint tokens) public returns(bool success);

  function setAccountInformation(address account, string memory information) public returns(bool);

  function startNow() public;

  event Transfer(address indexed from, address indexed to, uint tokens);
  event Approval(address indexed tokenOwner, address indexed spender, uint tokens);

}

contract ClaimInterface {
  function claimRange(uint fromBlock, uint toBlock) public returns(bool);

  function claimRange(address rewardAddress, uint fromBlock, uint toBlock) public returns(bool);

  function claimAt(uint blocknumber) public returns(bool);

  function claimAt(address rewardAddress, uint blocknumber) public returns(bool);

  function claim() public returns(bool);

  function claim(address rewardAddress) public returns(bool);

  function rewardsTotal() public view returns(uint);

  function markRewarded(address rewardAddress) internal;
}

// ----------------------------------------------------------------------------
// Contract function to receive approval and execute function in one call
//
// Borrowed from MiniMeToken
// ----------------------------------------------------------------------------

contract ApproveAndCallFallBack {

  function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public;

}

// ----------------------------------------------------------------------------
// Owned contract
// ----------------------------------------------------------------------------

contract Owned {

  address public owner;
  address public newOwner;

  event OwnershipTransferred(address indexed _from, address indexed _to);

  constructor() public {
    owner = msg.sender;
  }

  modifier onlyOwner {
    require(msg.sender == owner);
    _;
  }

  function transferOwnership(address _newOwner) public onlyOwner {
    newOwner = _newOwner;
  }

  function acceptOwnership() public {
    require(msg.sender == newOwner);
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
    newOwner = address(0);
  }

}

contract presaleLock is Owned {
  bool locked = true;

  function startNow() public {
    require(address(msg.sender) == address(owner));
    locked = false;
  }
}

contract Mining is presaleLock {
  using SafeMath
  for uint;
  using ExtendedMath
  for uint;

  uint public nextSolution;
  uint public tokensMinted;
  uint public _totalSupply;
  uint8 public decimals;
  uint public rewardEra;
  uint public lastRewardEthBlockNumber;
  uint public blockCount; //number of 'blocks' mined
  uint public lastBlock = _BLOCKS_PER_READJUSTMENT.mul(38); //the last block to be mined
  uint public timeDifficulty;
  mapping(uint => uint) minedTokens; // miningEpoch, minedTokens
  uint public maxSupplyForEra;
  uint public _BLOCKS_PER_READJUSTMENT = 1024;
  mapping(uint => uint) endOfBlock; // miningEpoch, endOfEpoch
  bytes32 public challengeNumber; //generate a new one when a new reward is minted
  uint public latestDifficultyPeriodStarted;
  uint public miningTarget;
  uint public _MAXIMUM_TARGET = 2 ** 234;
  uint public _MINIMUM_TARGET = 2 ** 16;
  uint public minTimeDuration = 500; //BTC historical data shows the average of 570 seconds per block, we are using 500 which will be readjusted.

  function getMiningReward() public view returns(uint) {
    require(!locked);
    return (50 * 10 ** uint(decimals)).div(2 ** rewardEra);
  }

  function mine() internal returns(bool success) {
    require(!locked);
    if ((now < nextSolution) ||
      (tokensMinted.add(getMiningReward()) > _totalSupply) ||
      (rewardEra >= 38)) {
      return true;
    }

    uint reward_amount = getMiningReward();
    tokensMinted = tokensMinted.add(reward_amount);
    lastRewardEthBlockNumber = block.number;
    _startNewMiningEpoch();

    //instead of minting, we queue it in a pool
    minedTokens[blockCount - 1] = reward_amount;

    nextSolution = now + timeDifficulty;

    return true;
  }

  //a new 'block' to be mined
  function _startNewMiningEpoch() internal {
    require(!locked);
    //if max supply for the era will be exceeded next reward round then enter the new era before that happens
    //40 is the final reward era, almost all tokens minted
    //once the final era is reached, more tokens will not be given out because of the assert function
    if (tokensMinted.add(getMiningReward()) > maxSupplyForEra && rewardEra < 39) {
      rewardEra = rewardEra + 1;
    }
    //set the next minted supply at which the era will change
    // total supply is 2100000000000000  because of 8 decimal places
    maxSupplyForEra = _totalSupply - _totalSupply.div(2 ** (rewardEra + 1));
    blockCount = blockCount.add(1);
    //every so often, readjust difficulty. Dont readjust when deploying
    if (blockCount % _BLOCKS_PER_READJUSTMENT == 0) {
      _reAdjustDifficulty();
    }
    endOfBlock[blockCount] = now + timeDifficulty;
    //make the latest ethereum block hash a part of the next challenge for PoW to prevent pre-mining future blocks
    //do this last since this is a protection mechanism in the mint() function
    challengeNumber = blockhash(block.number - 1);
  }

  //https://en.bitcoin.it/wiki/Difficulty#What_is_the_formula_for_difficulty.3F
  //as of 2017 the bitcoin difficulty was up to 17 zeroes, it was only 8 in the early days
  //readjust the target by 5 percent
  function _reAdjustDifficulty() internal {
    require(!locked);
    uint ethBlocksSinceLastDifficultyPeriod = block.number - latestDifficultyPeriodStarted;
    //assume 360 ethereum blocks per hour
    //we want miners to spend 10 minutes to mine each 'block', about 60 ethereum blocks = one BitcoinSoV epoch
    uint epochsMined = _BLOCKS_PER_READJUSTMENT; //256
    uint targetEthBlocksPerDiffPeriod = epochsMined * 60; //should be 60 times slower than ethereum
    //if there were less eth blocks passed in time than expected
    uint oldTarget = miningTarget;
    if (ethBlocksSinceLastDifficultyPeriod < targetEthBlocksPerDiffPeriod) {
      uint excess_block_pct = (targetEthBlocksPerDiffPeriod.mul(100)).div(ethBlocksSinceLastDifficultyPeriod);
      uint excess_block_pct_extra = excess_block_pct.sub(100).min(1000);
      // If there were 5% more blocks mined than expected then this is 5.  If there were 100% more blocks mined than expected then this is 100.
      //make it harder
      miningTarget = miningTarget.sub(miningTarget.div(2000).mul(excess_block_pct_extra)); //by up to 50 %

      uint permile = (miningTarget.mul(1000)).div(oldTarget); //difficulty in permiles
      timeDifficulty = timeDifficulty.add((timeDifficulty.mul(permile)).div(1000));

    } else {
      uint shortage_block_pct = (ethBlocksSinceLastDifficultyPeriod.mul(100)).div(targetEthBlocksPerDiffPeriod);
      uint shortage_block_pct_extra = shortage_block_pct.sub(100).min(1000); //always between 0 and 1000
      //make it easier
      miningTarget = miningTarget.add(miningTarget.div(2000).mul(shortage_block_pct_extra)); //by up to 50 %

      uint permile = (oldTarget.mul(1000)).div(miningTarget); //difficulty in permiles
      timeDifficulty = timeDifficulty.sub((timeDifficulty.mul(permile)).div(1000));
    }
    latestDifficultyPeriodStarted = block.number;
    adjustDifficultyThresholds();

  }

  function adjustDifficultyThresholds() internal {
    require(!locked);
    if (miningTarget < _MINIMUM_TARGET) {
      miningTarget = _MINIMUM_TARGET;
    }
    if (miningTarget > _MAXIMUM_TARGET) {
      miningTarget = _MAXIMUM_TARGET;
    }
    if (timeDifficulty > 4099680000) {
      timeDifficulty = 4099680000;
    }
    if (timeDifficulty < minTimeDuration) {
      timeDifficulty = minTimeDuration;
    }
  }
}

contract Rewarding is ERC20Interface {

}

contract Claiming is ERC20Interface, ClaimInterface, Mining, Rewarding {

  mapping(uint => uint) totalClaims; // miningEpoch, totalClaims
  mapping(address => mapping(uint => bool)) rewardTaken; // miningEpoch, isRewardTaken?  (assumes flase as a default)
  mapping(address => mapping(uint => uint)) claims; //address => miningEpoch, claims | Keeps a track of all claims per miningEpoch for each address
  mapping(address => uint) lastRewardBlock; //the last blockCount of the rewards taken
  mapping(address => uint) balances;
  address public lastRewardTo;
  uint public lastRewardAmount;
  uint public weiPerCalim = 50000000000000; //Initial price of a coin per claim, 0.00005 ether
  bytes32 private stub; //used for claiming fees

  function claimRange(uint fromBlock, uint toBlock) public returns(bool) {
    return claimRange(msg.sender, fromBlock, toBlock);
  }

  function claimRange(address rewardAddress, uint fromBlock, uint toBlock) public returns(bool) {
    if (fromBlock < blockCount) {
      fromBlock = blockCount;
    }
    if (toBlock > lastBlock) {
      toBlock = lastBlock;
    }
    for (; fromBlock <= lastBlock; fromBlock++) {
      claimAt(rewardAddress, fromBlock);
    }
    return true;
  }

  function claimAt(uint blocknumber) public returns(bool) {
    return claimAt(msg.sender, blocknumber);
  }

  function claimAt(address rewardAddress, uint blocknumber) public returns(bool) {
    if (blocknumber >= blockCount) {
      rewardTaken[rewardAddress][blocknumber] = false;
    }
    claims[rewardAddress][blocknumber] = claims[rewardAddress][blocknumber].add(1); //adds a claim
    totalClaims[blocknumber] = totalClaims[blocknumber].add(1); //adds a claim to total claims
    mine();
    return true;
  }

  function claim() public returns(bool) {
    return claim(msg.sender);
  }

  function claim(address rewardAddress) public returns(bool) {
    uint fees = feesTotal(rewardAddress);
    require(block.gaslimit >= fees && gasleft() >= fees, "You must increase gas limits for this function call.");

    uint gweiTracker = gasleft();

    rewardTaken[rewardAddress][blockCount] = false;
    claims[rewardAddress][blockCount] = claims[rewardAddress][blockCount].add(1); //adds a claim
    totalClaims[blockCount] = totalClaims[blockCount].add(1); //adds a claim to total claims
    mine();
    takeAllRewards(rewardAddress);

    gweiTracker = gweiTracker.sub(gasleft());
    fees = fees.sub(gweiTracker); //these are the leftover fees
    uint endwhile = gasleft().sub(fees);

    //process the leftover fees
    while (gasleft() > endwhile) {
      stub = keccak256(abi.encodePacked(stub));
    }

    return true;
  }

  function rewardsTotal() public view returns(uint) {
    return rewardsTotal(msg.sender);
  }

  function rewardsTotal(address rewardAddress) public view returns(uint) {
    uint rewards = 0;
    uint blockID = lastRewardBlock[rewardAddress];
    if (blockID > 10) {
      blockID = blockID.sub(10);
    } else {
      blockID = 0;
    }
    for (; blockID < blockCount; blockID++) {
      uint totalClaimsInBlock = totalClaims[blockID];
      uint totalClaimsForUser = claims[rewardAddress][blockID];
      if (totalClaimsInBlock > 0) {
        uint reward = (totalClaimsForUser.div(totalClaimsInBlock)).mul(minedTokens[blockID]);
        rewards = rewards.add(reward);
      }
    }
    return rewards;
  }

  function feesTotal(address rewardAddress) public view returns(uint) {
    uint fees = 0;
    uint blockID = lastRewardBlock[rewardAddress];
    if (blockID > 10) {
      blockID = blockID.sub(10);
    } else {
      blockID = 0;
    }
    for (; blockID < blockCount; blockID++) {
      uint totalClaimsInBlock = totalClaims[blockID];
      uint totalClaimsForUser = claims[rewardAddress][blockID];
      if (totalClaimsInBlock > 0) {
        uint reward = (totalClaimsForUser.div(totalClaimsInBlock)).mul(minedTokens[blockID]);
        uint fee = (((blockID.div(_BLOCKS_PER_READJUSTMENT)).add(1)).mul(weiPerCalim)).mul(reward);
        fees = fees.add(fee);
      }
    }
    fees = (fees.div(1000000000)).div(10 ** uint(decimals)); //in gwei per token
    return fees;
  }

  function markRewarded(address rewardAddress) internal {
    require(!locked);
    for (uint blockID = 0; blockID < blockCount; blockID++) {
      rewardTaken[rewardAddress][blockID] = true;
    }
  }

  function takeAllRewards(address rewardAddress) private returns(bool) {
    require(!locked);
    uint rewards = rewardsTotal(rewardAddress);
    require(rewards > 0);

    emit Transfer(address(0), rewardAddress, rewards);
    balances[rewardAddress] = balances[rewardAddress].add(rewards);
    lastRewardTo = rewardAddress;
    lastRewardAmount = rewards;
    lastRewardEthBlockNumber = block.number;
    rewardTaken[rewardAddress][blockCount] = true;
    markRewarded(rewardAddress);
    lastRewardBlock[rewardAddress] = blockCount;

    return true;
  }

}

contract Transfers is Claiming {
  using SafeMath
  for uint;

  uint public tokensBurned;
  mapping(address => mapping(address => uint)) allowed;

  function transfer(address to, uint tokens) public returns(bool success) {
    require(!locked);

    balances[msg.sender] = balances[msg.sender].sub(tokens);
    balances[to] = balances[to].add(tokens);
    emit Transfer(msg.sender, to, tokens);

    return true;
  }

  function approve(address spender, uint tokens) public returns(bool success) {
    require(!locked);
    allowed[msg.sender][spender] = tokens;
    emit Approval(msg.sender, spender, tokens);
    return true;
  }

  function transferFrom(address from, address to, uint tokens) public returns(bool success) {
    require(!locked);
    balances[from] = balances[from].sub(tokens);
    allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
    balances[to] = balances[to].add(tokens);
    emit Transfer(from, to, tokens);
    return true;
  }

  function allowance(address tokenOwner, address spender) public view returns(uint remaining) {
    require(!locked);
    return allowed[tokenOwner][spender];
  }

  function approveAndCall(address spender, uint tokens, bytes memory data) public returns(bool success) {
    require(!locked);
    allowed[msg.sender][spender] = tokens;
    emit Approval(msg.sender, spender, tokens);
    ApproveAndCallFallBack(spender).receiveApproval(msg.sender, tokens, address(this), data);
    return true;
  }

}

contract Views is Transfers {

  //this is a recent ethereum block hash, used to prevent pre-mining future blocks
  function getChallengeNumber() public view returns(bytes32) {
    return challengeNumber;
  }

  //the number of zeroes the digest of the PoW solution requires.  Auto adjusts
  function getMiningDifficulty() public view returns(uint) {
    return _MAXIMUM_TARGET.div(miningTarget);
  }

  function getMiningTarget() public view returns(uint) {
    return miningTarget;
  }

  function getCurrentTime() public view returns(uint) {
    return now;
  }

  // ------------------------------------------------------------------------
  // Total supply
  // ------------------------------------------------------------------------

  function totalSupply() public view returns(uint) {
    return _totalSupply - balances[address(0)];
  }

  // ------------------------------------------------------------------------
  // Get the token balance for account `tokenOwner`
  // ------------------------------------------------------------------------

  function balanceOf(address tokenOwner) public view returns(uint balance) {
    return balances[tokenOwner];
  }

}

contract Chronos is Owned, Views {

  string public symbol;
  string public name;
  mapping(address => string) accountInformation; //the last blockCount of the rewards taken

  bool locked = false;

  // ------------------------------------------------------------------------
  // Constructor
  // ------------------------------------------------------------------------

  constructor() public onlyOwner {
    symbol = "BTCHR";
    name = "Bitcoin Chronos";
    decimals = 8;
    _totalSupply = 21000000 * 10 ** uint(decimals);
    if (locked) revert();
    locked = true;
    tokensMinted = 0;
    rewardEra = 0;
    maxSupplyForEra = _totalSupply.div(2);
    miningTarget = _MAXIMUM_TARGET;
    latestDifficultyPeriodStarted = block.number;
    timeDifficulty = minTimeDuration;
    nextSolution = now + timeDifficulty;
    _startNewMiningEpoch();
  }

  function getAccountInformation(address account) public view returns(string memory remaining) {
    return accountInformation[account];
  }

  function setAccountInformation(address account, string memory information) public returns(bool) {
    accountInformation[account] = information;
    return true;
  }

  // ------------------------------------------------------------------------
  // Owner can transfer out any accidentally sent ERC20 tokens
  // ------------------------------------------------------------------------

  function transferAnyERC20Token(address tokenAddress, uint tokens) public onlyOwner returns(bool success) {
    require(!locked);
    return ERC20Interface(tokenAddress).transfer(owner, tokens);
  }

  // ------------------------------------------------------------------------
  // Don't accept ETH
  // ------------------------------------------------------------------------

  function () external payable {
    revert();
  }

}
