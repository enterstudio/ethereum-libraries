pragma solidity ^0.4.15;

/**
 * @title EvenDistroCrowdsaleLib
 * @author Majoolr.io
 *
 * version 1.0.0
 * Copyright (c) 2017 Majoolr, LLC
 * The MIT License (MIT)
 * https://github.com/Majoolr/ethereum-libraries/blob/master/LICENSE
 *
 * The EvenDistroCrowdsale Library provides functionality to create a initial coin offering
 * for a standard token sale with high demand where the amount of ether a single address
 * can contribute is calculated by dividing the sale's contribution cap by the number 
 * of addresses who register before the sale starts
 *
 *
 * Test Crowdsale allows for testing in testrpc by allowing a paramater, currtime, to be passed
 * to functions that would normally require a now variable.  This allows testrpc testing
 * without having to add delays in the code to time it perfectly.  This also replaces some require() statements
 * to regular conditional checks to allow for better testing.
 *
 * See https://github.com/Majoolr/ethereum-contracts for an example of how to
 * create a basic ERC20 token.
 *
 * Majoolr works on open source projects in the Ethereum community with the
 * purpose of testing, documenting, and deploying reusable code onto the
 * blockchain to improve security and usability of smart contracts. Majoolr
 * also strives to educate non-profits, schools, and other community members
 * about the application of blockchain technology.
 * For further information: majoolr.io
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import "./BasicMathLib.sol";
import "./TokenLib.sol";
import "./TestCrowdsaleLib.sol";

library TestEvenDistroCrowdsaleLib {
  using BasicMathLib for uint256;
  using TestCrowdsaleLib for TestCrowdsaleLib.CrowdsaleStorage;

  struct EvenDistroCrowdsaleStorage {

  	TestCrowdsaleLib.CrowdsaleStorage base;

    // mapping showing which addresses have registered for the sale. can only be changed by the owner
    mapping (address => bool) isRegistered;

    uint256 numRegistered;   // records how many addresses have registered
    uint256 addressCap;           // cap on how much wei an address can contribute in the sale
    uint256 capPercentMultiplier;  // percent of the address cap that we multiply to increase every time interval

    uint256 changeInterval;      // amount of time between changes in the purchase cap for each address
    uint256 lastCapChangeTime;  // time of the last change in token cost
  }

  // Indicates when tokens are bought during the sale
  event LogTokensBought(address indexed buyer, uint256 amount);
  
  // Logs when a buyer has exceeded the address cap and tells them to withdraw their leftover wei
  event LogAddressCapExceeded(address indexed buyer, uint256 amount, string Msg);

  // Logs when a user is registered in the system before the sale
  event LogUserRegistered(address registrant);

  // Logs when a user is unregistered from the system before the sale
  event LogUserUnRegistered(address registrant);

  // Logs when there is an error
  event LogErrorMsg(uint256 amount, string Msg);

  // Logs when there is an increase in the contribution cap per address
  event LogAddressCapChange(uint256 amount, string Msg);

  // Logs when the address cap is initially calculated
  event LogAddressCapCalculated(uint256 saleCap, uint256 numRegistered, uint256 cap, string Msg);


  /// @dev Called by a crowdsale contract upon creation.
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _owner Address of crowdsale owner
  /// @param _capAmountInCents Total to be raised in cents
  /// @param _startTime Timestamp of sale start time
  /// @param _endTime Timestamp of sale end time
  /// @param _fallbackExchangeRate Exchange rate of cents/ETH
  /// @param _changeInterval The number of seconds between each step
  /// @param _percentBurn Percentage of extra tokens to burn
  /// @param _capPercentMultiplier percent of the address cap that we multiply to increase every time interval
  /// @param _token Token being sold
  function init(EvenDistroCrowdsaleStorage storage self,
                address _owner,
                uint256 _capAmountInCents,
                uint256 _startTime,
                uint256 _endTime,
                uint256 _tokenPriceinCents,
                uint256 _fallbackExchangeRate,
                uint256 _changeInterval,
                uint8 _percentBurn,
                uint256 _capPercentMultiplier,
                uint256 _fallbackAddressCap,
                CrowdsaleToken _token)
  {
    self.base.init(_owner,
                _tokenPriceinCents,
                _fallbackExchangeRate,
                _capAmountInCents,
                _startTime,
                _endTime,
                _percentBurn,
                _token);


    if(_changeInterval == 0) {
      require(_capPercentMultiplier == 100);
    } else {
      require(_capPercentMultiplier > 100);
    }
    require(_fallbackAddressCap > 0);
    require(_capPercentMultiplier < 10000);
    self.capPercentMultiplier = _capPercentMultiplier;
    self.changeInterval = _changeInterval;
    self.lastCapChangeTime = _startTime;
    self.addressCap = _fallbackAddressCap;
  }

  /// @dev register user function. can only be called by the owner when a user registers on the web app.
  /// puts their address in the registered mapping and increments the numRegistered
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _registrant address to register for the sale
  function registerUser(EvenDistroCrowdsaleStorage storage self, address _registrant, uint256 currtime) returns (bool) {
    require(msg.sender == self.base.owner);
    if ((self.changeInterval > 0) && (currtime >= self.base.startTime - 3)) {
      LogErrorMsg(self.base.startTime-1, "Cannot register users within 1 days of the sale!");
      return false;
    }
    if(self.isRegistered[_registrant]) {
      LogErrorMsg(currtime, "Registrant address is already registered for the sale!");
      return false;
    }

    uint256 result;
    bool err;

    self.isRegistered[_registrant] = true;
    (err,result) = self.numRegistered.plus(1);
    require(!err);
    self.numRegistered = result;

    LogUserRegistered(_registrant);

    return true;
  }

  /// @dev registers multiple users at the same time
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _registrants addresses to register for the sale
  function registerUsers(EvenDistroCrowdsaleStorage storage self, address[] _registrants, uint256 currtime) returns (bool) {
    require(msg.sender == self.base.owner);
    if (self.changeInterval > 0) { require(currtime < self.base.startTime - 3); }
    bool ok;

    for (uint256 i = 0; i < _registrants.length; i++) {
      ok = registerUser(self,_registrants[i],currtime);
    }
  }

  /// @dev Cancels a user's registration status can only be called by the owner when a user cancels their registration.
  /// sets their address field in the registered mapping to false and decrements the numRegistered
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _registrant address to unregister from the sale
  function unregisterUser(EvenDistroCrowdsaleStorage storage self, address _registrant, uint256 currtime) returns (bool) {
    require(msg.sender == self.base.owner);
    if ((self.changeInterval > 0) && (currtime >= self.base.startTime - 3)) {
      LogErrorMsg(self.base.startTime-1, "Cannot unregister users within 1 days of the sale!");
      return false;
    }
    if(!self.isRegistered[_registrant]) {
      LogErrorMsg(currtime, "Registrant address not registered for the sale!");
      return false;
    }

    uint256 result;
    bool err;

    self.isRegistered[_registrant] = false;
    (err,result) = self.numRegistered.minus(1);
    require(!err);
    self.numRegistered = result;

    LogUserUnRegistered(_registrant);

    return true;
  }

  /// @dev unregisters multiple users at the same time
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _registrants addresses to unregister for the sale
  function unregisterUsers(EvenDistroCrowdsaleStorage storage self, address[] _registrants, uint256 currtime) returns (bool) {
    require(msg.sender == self.base.owner);
    if (self.changeInterval > 0) { require(currtime < self.base.startTime - 3); }

    bool ok;

    for (uint256 i = 0; i < _registrants.length; i++) {
      ok = unregisterUser(self,_registrants[i],currtime);
    }
  }

  /// @dev function that calculates address cap from the number of users registered 
  /// @param self Stored crowdsale from crowdsale contract
  function calculateAddressCap(EvenDistroCrowdsaleStorage storage self, uint256 currtime) internal returns (bool) {
    require(self.numRegistered > 0);
    if ((currtime > self.base.startTime) || (currtime < (self.base.startTime - 3)) || (self.changeInterval == 0))  {
      return false;
    }
    if(self.base.rateSet) { return false; }  //make's sure this can only be called once

    uint256 result;
    bool err;

    (err,result) = self.base.capAmount.dividedBy(self.numRegistered);
    require(!err);

    self.addressCap = result;

    LogAddressCapCalculated(self.base.capAmount,self.numRegistered,result,"Address cap was Calculated!");
  }

  /// @dev utility function for the receivePurchase function. returns the lower number
  /// @param a first argument
  /// @param b second argument
  function getMin(uint256 a, uint256 b) internal constant returns (uint256) {
    if (a<b) { return a; } else { return b; }
  }

  /// @dev Called when an address wants to purchase tokens
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _amount amound of wei that the buyer is sending
  function receivePurchase(EvenDistroCrowdsaleStorage storage self, uint256 _amount, uint256 currtime) returns (bool) {
    if(msg.sender == self.base.owner) {
      LogErrorMsg(msg.value, "Owner cannot send ether to contract");
      return false;
    }      
    if (!self.base.validPurchase(currtime)) {
      return false;
    }
    if ((self.base.ownerBalance + _amount) > self.base.capAmount) {
      LogErrorMsg(msg.value, "buyer ether sent exceeds cap of ether to be raised!");
      return false;
    }
    if(!self.isRegistered[msg.sender]) {
      LogErrorMsg(msg.value, "Buyer is not registered for the sale!");
      return false;
    }

    bool err;
    uint256 result;

    // if the address cap increase interval has passed, update the current day and change the address cap
    if ((self.changeInterval > 0) && (currtime >= (self.lastCapChangeTime + self.changeInterval))) {
      // calculate the number of change intervals that have passed since the last change
      uint256 numIntervals = (((currtime-(currtime%self.changeInterval))-self.lastCapChangeTime)/self.changeInterval);

      // multiply by the percentage multiplier for each interval that has passed  
      (err,result) = self.addressCap.times(self.capPercentMultiplier ** (numIntervals));
      require(!err);

      // fix the decimal point
      (err,result) = result.dividedBy(100**numIntervals);
      require(!err);
      self.addressCap = result;

      // set the new change time
      self.lastCapChangeTime = self.lastCapChangeTime + (self.changeInterval*numIntervals);

      LogAddressCapChange(result, "Address cap has increased!");
    }

  	uint256 numTokens; //number of tokens that will be purchased
    uint256 zeros; //for calculating token
    uint256 leftoverWei; //wei change for purchaser if they went over the address cap
    uint256 remainder = 0; //temp calc holder for division remainder and then tokens remaining for the owner

    uint256 allowedWei;  // tells how much more the buyer can contribute up to their cap
    (err,allowedWei) = self.addressCap.minus(self.base.hasContributed[msg.sender]);
    require(!err);

    allowedWei = getMin(_amount,allowedWei);
    leftoverWei = _amount - allowedWei;

    // Find the number of tokens as a function in wei
    (err,result) = allowedWei.times(self.base.tokensPerEth);
    require(!err);

    if(self.base.tokenDecimals <= 18){
      zeros = 10**(18-uint256(self.base.tokenDecimals));
      numTokens = result/zeros;
      remainder = result % zeros;
    } else {
      zeros = 10**(uint256(self.base.tokenDecimals)-18);
      numTokens = result*zeros;
    }

    self.base.leftoverWei[msg.sender] += leftoverWei+remainder;
    if(((self.base.hasContributed[msg.sender] + _amount)) > self.addressCap) {
      LogAddressCapExceeded(msg.sender,self.base.leftoverWei[msg.sender],"Cap Per Address has been exceeded! Please withdraw leftover Wei!");
    }

    // can't overflow because it is under the cap
    self.base.hasContributed[msg.sender] += allowedWei - remainder;

    require(numTokens <= self.base.token.balanceOf(this));

    // calculate the amout of ether in the owners balance and "deposit" it
    self.base.ownerBalance = self.base.ownerBalance + (allowedWei - remainder);

    // can't overflow because it will be under the cap
    self.base.withdrawTokensMap[msg.sender] += numTokens;

    //subtract tokens from owner's share
    (err,remainder) = self.base.withdrawTokensMap[self.base.owner].minus(numTokens);
    require(!err);
    self.base.withdrawTokensMap[self.base.owner] = remainder;

    LogTokensBought(msg.sender, numTokens);

    return true;
  }

  ///  Functions "inherited" from CrowdsaleLib library
  function setTokenExchangeRate(EvenDistroCrowdsaleStorage storage self, uint256 _exchangeRate, uint256 _currtime) returns (bool) {
    bool ok = calculateAddressCap(self,_currtime);

    return self.base.setTokenExchangeRate(_exchangeRate, _currtime) && ok;
  }

  function crowdsaleActive(EvenDistroCrowdsaleStorage storage self, uint256 currtime) constant returns (bool) {
    return self.base.crowdsaleActive(currtime);
  }

  function crowdsaleEnded(EvenDistroCrowdsaleStorage storage self, uint256 currtime) constant returns (bool) {
    return self.base.crowdsaleEnded(currtime);
  }

  function validPurchase(EvenDistroCrowdsaleStorage storage self, uint256 currtime) constant returns (bool) {
    return self.base.validPurchase(currtime);
  }

  function withdrawTokens(EvenDistroCrowdsaleStorage storage self,uint256 currtime) returns (bool) {
    return self.base.withdrawTokens(currtime);
  }

  function withdrawLeftoverWei(EvenDistroCrowdsaleStorage storage self) returns (bool) {
    return self.base.withdrawLeftoverWei();
  }

  function withdrawOwnerEth(EvenDistroCrowdsaleStorage storage self,uint256 currtime) returns (bool) {
    return self.base.withdrawOwnerEth(currtime);
  }

}
