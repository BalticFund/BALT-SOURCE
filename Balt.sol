pragma solidity ^0.4.19;
import '../node_modules/zeppelin-solidity/contracts/token/ERC20/SafeERC20.sol';
import '../node_modules/zeppelin-solidity/contracts/token/ERC20/StandardToken.sol';
import '../node_modules/zeppelin-solidity/contracts/math/Math.sol';
import '../node_modules/zeppelin-solidity/contracts/math/SafeMath.sol';
import '../node_modules/zeppelin-solidity/contracts/ownership/Ownable.sol';
import './DateTime.sol';

contract BaltToken is StandardToken, Ownable {
    string public constant name = "Baltic Fund Token";
    string public constant symbol = "BALT";
    uint8 public constant decimals = 16;
    uint256 public constant INITIAL_SUPPLY = 165000000 * (10 ** uint256(decimals));  //165M tokens

    /**
    * @dev Constructor that gives msg.sender all existing tokens.
    */
    function BaltToken() Ownable() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;

    }

    /**
     * @dev changes the owner and transfers all remaining tokens to the new owner
     */
    function setOwnerAndTransferTokens(address _newOwner) public onlyOwner {
        transferOwnership(_newOwner);
        transfer(_newOwner, balances[msg.sender]);
    }

    /**
     * @dev Don't send ether to this address (send to the CrowdSale contract instead)
     */
    function() public payable {
        revert();
    }

    /////////// BOUNTY RELATED FUNCTIONALITY //////////
    mapping (address => bool) private investors;    //all ICO participants
    mapping (address => bool) private bountyHunters;
    address[] private huntersArray;
    uint256 private bountyLockEndTime;


    /**
     * @dev add a participant (so that a bounty hunter could send them tokens)
     */
    function addInvestor(address investor) public onlyOwner {
        investors[investor] = true;
    }

    /**
     * @dev mark this address as BountyHunter
     */
    function markAsBountyHunter(address hunter) public onlyOwner {
        bountyHunters[hunter] = true;
        huntersArray.push(hunter);
    }

    function unmarkAsBountyHunter(address hunter) public onlyOwner {
        bountyHunters[hunter] = false;
        for (uint8 index = 0; index < huntersArray.length; index++) {
            if (huntersArray[index] == hunter) {
                delete huntersArray[index];
            }
        }
    }

    function getHunters() public view returns(address[]) {
        return huntersArray;
    }

    /**
     * @dev set the lock end time for bounty tokens
     */
    function setBountyLockEndTime(uint16 year, uint8 month, uint8 day, uint8 hour) public onlyOwner {
        bountyLockEndTime = new DateTime().toTimestamp(year, month, day, hour);
    }

    /**
     * @dev Overrides the default transfer function to block bounty owners from transferring until the lock date
     */
    function transfer(address to, uint256 value) public returns (bool) {
        require(!bountyHunters[msg.sender] || investors[to] || bountyHunters[to] || now > bountyLockEndTime);
        return super.transfer(to, value);
    }
}

contract ICO is Ownable {
    using SafeERC20 for BaltToken;
    using SafeMath for uint256;
    BaltToken private token;
    uint256 investorCount = 0;
    DateTime dateUtil = new DateTime();
    event Log(string message);
    event LogNum(uint256 message);


    /**
     * @dev Constructor -- initializes various time constants, sets the reference to the token contract
     */
    function ICO(address _tokenAddress) Ownable() public {
        token = BaltToken(_tokenAddress);
    }

    /**
     * @dev changeTokenOwner
     */
    function changeTokenOwner(address _newOwner) public onlyOwner {
        token.setOwnerAndTransferTokens(_newOwner);
    }

    /**
     * @dev Send tokens according to the current rate/bonus
     */
    function() public payable {
        require(currentStage() != Stage.Paused);
        distributeTokens();
        investorCount += 1; //for presale bonus
        token.addInvestor(msg.sender);  //add the investor to the list, so that Bounty Hunters can send tokens to her
        forwardFunds();
    }

    /////////// UNPAID TOKENS /////////
    mapping (address => uint256) private unpaidTokens;
    address[] private unpaidInvestors;

    function getUnpaidBalance(address investor) public view onlyOwner returns(uint256){
        return unpaidTokens[investor];
    }

    function removeFromUnpaid(address investor) public onlyOwner {
        unpaidTokens[investor] = 0;
        for (uint8 index = 0; index < unpaidInvestors.length; index++) {
            if (unpaidInvestors[index] == investor)
                delete unpaidInvestors[index];
        }
    }

    function getUnpaidInvestors()  public view onlyOwner returns(address[]){
        return unpaidInvestors;
    }

    /**
     * Send tokens to the investor
     */
    function distributeTokens() private {
        uint256 tokenPrice = getPrice();
        uint256 tokensPurchased = msg.value.mul(10 ** uint256(token.decimals())).div(tokenPrice).mul(getRate()).div(100);
        //Greetings to ICO hackers
        if (isEasterEggPayment()) {
            tokensPurchased = tokensPurchased.mul(150).div(100);
            hackers[msg.sender] = true;
            hackersCount += 1;
        }

        //(code below untested)
        if(msg.value >= 300 ether)
            tokensPurchased = tokensPurchased.mul(105).div(100);    // 300+ETH purchase +5%
        else {
            if(msg.value >= 100 ether)
                tokensPurchased = tokensPurchased.mul(102).div(100);    //100+ ETH purchase +2%

        }

        //if < 100 tokens, revert
        if (tokensPurchased < 100 * (10 ** uint256(token.decimals()))) {
            revert();
        }

        //if the sender is not KYC-ed, and she sends >10ETH, hold the tokens and send after KYC
        if (whalesAfterKyc[msg.sender])
            token.safeTransfer(msg.sender, tokensPurchased);
        else {
            unpaidTokens[msg.sender] += tokensPurchased;
            for (uint8 index = 0; index < unpaidInvestors.length; index++) {
                if (unpaidInvestors[index] == msg.sender)
                    delete unpaidInvestors[index];
            }
            unpaidInvestors.push(msg.sender);
        }



    }

    /**
     * @dev Just send the tokens
     * @param addressee where to send
     * @param amount how many tokens to send
     */
    function sendTokens(address addressee, uint256 amount) public onlyOwner {
        token.safeTransfer(addressee, amount);
    }

    /////////////// BOUNTY //////////////

    /**
     * @dev Send bounty tokens
     * @param hunter where to send
     * @param amount how many tokens to send
     */
    function sendBountyTokens(address hunter, uint256 amount) public onlyOwner {
        token.safeTransfer(hunter, amount);
        token.markAsBountyHunter(hunter);
    }

    function unmarkAsBountyHunter(address hunter) public onlyOwner {
        token.unmarkAsBountyHunter(hunter);
    }

    // function getHunters() public view onlyOwner returns(address[]) {
    //     return token.getHunters();
    // }

    /**
     * @dev send tokens after KYC
     */
    function sendUnpaidTokens(address investor) public onlyOwner {
        token.safeTransfer(investor, unpaidTokens[investor]);
        removeFromUnpaid(investor);
        addVerifiedAddress(investor);
    }


    /**
     * just forward the call to the token
     */
    function setBountyLockEndTime(uint16 year, uint8 month, uint8 day, uint8 hour) public onlyOwner {
        token.setBountyLockEndTime(year, month, day, hour);
    }

    /**
     * @dev send all received funds to the owner
     */
    function forwardFunds() internal {
        owner.transfer(msg.value);
    }

    ///////// PRE-APPROVED INVESTORS
    mapping (address => bool) private whalesAfterKyc;   //addresses from which we accept big payments
    address[] private whalesArray;

    /**
     * @dev Add an investor to a special list so that we could accept >10ETH from her
     * @param investor the address of the investor
     */
    function addVerifiedAddress(address investor) public onlyOwner {
        removeVerifiedAddress(investor);
        whalesAfterKyc[investor] = true;
        whalesArray.push(investor);
    }

    function removeVerifiedAddress(address investor) public onlyOwner {
        whalesAfterKyc[investor] = false;
        for (uint8 index = 0; index < whalesArray.length; index++) {
            if(whalesArray[index] == investor) {
                delete whalesArray[index];
            }
        }
    }

    function getVerifiedAddresses() public view onlyOwner returns(address[]) {
        return whalesArray;
    }

    ////////////// STAGES AND BONUSES //////////////
    uint256 private presaleStart = new DateTime().toTimestamp(2018, 2, 19, 10);     //Public pre-sale starts 12.00 EET February, 19, 2018 15% bonus First 250 customers get +2% bonus
    uint256 private presaleEnd = new DateTime().toTimestamp(2018, 3, 12, 10);       //Public pre-sale ends 12.00 EET March, 12, 2018 15% bonus ends
    uint256 private saleStart = new DateTime().toTimestamp(2018, 3, 19, 10);        //Public sale starts 12.00 EET March, 19, 2018 10% bonus
    uint256 private saleStart2 = new DateTime().toTimestamp(2018, 4, 16, 10);       //Public sale starts 12.00 EET April, 16, 2018 5% bonus
    uint256 private saleStart3 = new DateTime().toTimestamp(2018, 5, 7, 10);        //Public sale starts 12.00 EET May, 7, 2018 0% bonus
    uint256 private saleEnd = new DateTime().toTimestamp(2018, 6, 7, 10);           //Public sale ends 12.00 EET June, 7, 2018

    /**
     * @dev get token price (in Wei)
     */
    function getPrice() internal view returns (uint256) {
        if (currentStage() == Stage.Presale) {
            return 200000000000000;
        } else {
            return 250000000000000;
        }

    }

    /**
     * @dev get bonus rate, in percents (e.g. 115)
     */
    function getRate() internal view returns (uint8) {
        Stage stage = currentStage();
        if (stage == Stage.Presale) {
            return (investorCount >= 250) ? 115 : 117;//First 250 customers get +2% bonus
        }

        if (stage == Stage.Sale1)
            return 110;
        if (stage == Stage.Sale2)
            return 105;

        return 100;
    }

    ///EASTER EGG
    mapping (address => bool) hackers;
    uint8 public hackersCount = 0;
    /**
     * @dev easter egg handling
     */
    function isEasterEggPayment() internal view returns (bool) {
        if(!hackers[msg.sender] && hackersCount < 100)
            return msg.value == 197609220000000000;
        return false;
    }

    enum Stage {
        Presale,
        Sale1,
        Sale2,
        Sale3,
        Paused
    }

    /**
     * @dev returns current stage
     */
    function currentStage() internal view returns (Stage) {
        if (presaleStart < now && now < presaleEnd) {
            //Log('Presale');
            return Stage.Presale;
        }

        if (saleStart < now && now < saleStart2) {
            //Log('Sale1');
            return Stage.Sale1;
        }
        if (saleStart2 < now && now < saleStart3) {
            //Log('Sale2');
            return Stage.Sale2;
        }
        if (saleStart3 < now && now < saleEnd) {
            //Log('Sale3');
            return Stage.Sale3;
        }

        //Log('Paused');
        return Stage.Paused;
    }

    function setPresaleStartTime(uint16 year, uint8 month, uint8 day, uint8 hour) public onlyOwner {
        presaleStart = dateUtil.toTimestamp(year, month, day, hour);
    }

    function setPresaleEndTime(uint16 year, uint8 month, uint8 day, uint8 hour) public onlyOwner {
        presaleEnd = dateUtil.toTimestamp(year, month, day, hour);
    }

    function setSaleStartTime(uint16 year, uint8 month, uint8 day, uint8 hour) public onlyOwner {
        saleStart = dateUtil.toTimestamp(year, month, day, hour);
    }

    function setSaleStart2Time(uint16 year, uint8 month, uint8 day, uint8 hour) public onlyOwner {
        saleStart2 = dateUtil.toTimestamp(year, month, day, hour);
    }

    function setSaleStart3Time(uint16 year, uint8 month, uint8 day, uint8 hour) public onlyOwner {
        saleStart3 = dateUtil.toTimestamp(year, month, day, hour);
    }

    function setSaleEndTime(uint16 year, uint8 month, uint8 day, uint8 hour) public onlyOwner {
        saleEnd = dateUtil.toTimestamp(year, month, day, hour);
    }

    /**
     * @dev kill the contract and send all funds to the owner
     */
    function ownerKill() public onlyOwner {
        selfdestruct(owner);
    }
}
