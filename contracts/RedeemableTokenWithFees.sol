pragma solidity ^0.4.23;

import "./modularERC20/ModularPausableToken.sol";

/*
This allows for transaction fees to be assessed on transfer, burn, and mint.
The fee upon burning n tokens (other fees computed similarly) is:
(n * burnFeeNumerator / burnFeeDenominator) + burnFeeFlat
Note that what you think of as 1 TrueUSD token is internally represented
as 10^18 units, so e.g. a one-penny fee for burnFeeFlat would look like
burnFeeFlat = 10^16
The fee for transfers is paid by the recipient.
*/
contract RedeemableTokenWithFees is ModularPausableToken {
    string public constant NO_FEES = "noFees";

    event ChangeStaker(address indexed addr);
    event RedemptionAddressCountIncremented(uint count);

    event ChangeStakingFees(
    uint256 transferFeeNumerator,
    uint256 transferFeeDenominator,
    uint256 mintFeeNumerator,
    uint256 mintFeeDenominator,
    uint256 mintFeeFlat,
    uint256 burnFeeNumerator,
    uint256 burnFeeDenominator,
    uint256 burnFeeFlat);

    /**
    * @dev pay staking fee for mints. Mint fee would be zero if 0x0 has attribute noFees in registry
    Address who receive the mint pays mint fee
    */
    function mint(address _to, uint256 _value) public onlyOwner returns (bool) {
        bool result = super.mint(_to, _value);
        payStakingFee(_to, _value, mintFeeNumerator, mintFeeDenominator, mintFeeFlat, address(0));
        return result;
    }

    /**
    * @dev pay staking fee for burns. Burn fee would be zero if 0x0 has attribute noFees in registry
    Address who burns pays burn fee
    */
    function burnAllArgs(address _burner, uint256 _value, string _note) internal {
        uint256 fee = payStakingFee(_burner, _value, burnFeeNumerator, burnFeeDenominator, burnFeeFlat, address(0));
        uint256 remaining = _value.sub(fee);
        super.burnAllArgs(_burner, remaining, _note);
    }

    // transfer and transferFrom both call this function, so pay staking fee here.
    //if A transfers 1000 tokens to B, B will receive 999 tokens, and the staking contract will receiver 1 token.
    function transferAllArgs(address _from, address _to, uint256 _value) internal {
        if (_to == address(0)) {
            burnAllArgs(_from, _value, "");
        } else if (uint(_to) <= redemptionAddressCount) {
            super.transferAllArgs(_from, _to, _value);
            burnAllArgs(_to, _value, "");
        } else {
            uint256 fee = payStakingFee(_from, _value, transferFeeNumerator, transferFeeDenominator, 0, _to);
            uint256 remaining = _value.sub(fee);
            super.transferAllArgs(_from, _to, remaining);
        } 
    }


    // StandardToken's transferFrom doesn't have to check for
    // _to != 0x0, but we do because we redirect 0x0 transfers to burns, but
    // we do not redirect transferFrom
    function transferFromAllArgs(address _from, address _to, uint256 _value, address _spender) internal {
        require(_to != address(0), "_to address is 0x0");
        super.transferFromAllArgs(_from, _to, _value, _spender);
    }

    function incrementRedemptionAddressCount() external onlyOwner {
        redemptionAddressCount += 1;
        emit RedemptionAddressCountIncremented(redemptionAddressCount);
    }

    /** 
    @dev calculates staking fee based on the type of transaction and user, and transfers fee to the staker address
    @param _payer address that pays the staking fee
    @param _value amount of tokens to transfer/mint/burn
    @param _numerator numerator depending on the type of transaction
    @param _denominator denominator depending on the type of transaction
    @param _flatRate flat rate on top of floating rate
    @param _otherParticipant 0 address for mint and burn, to address for transfer
    @return uint256 returns amount of fee paid 
    */
    function payStakingFee(
        address _payer,
        uint256 _value,
        uint256 _numerator,
        uint256 _denominator,
        uint256 _flatRate,
        address _otherParticipant) private returns (uint256) {
        // This check allows accounts to be whitelisted and not have to pay transaction fees.
        if (hasNoFee(_payer, _otherParticipant)) {
            return 0;
        }
        uint256 stakingFee = _value.mul(_numerator).div(_denominator).add(_flatRate);
        if (stakingFee > 0) {
            super.transferAllArgs(_payer, staker, stakingFee);
        }
        return stakingFee;
    }

    /** 
    @dev returns true if either party has the property 'noFee'
    */
    function hasNoFee(address _from, address _to) public view returns (bool) {
        return registry.hasAttribute(_from, NO_FEES) || registry.hasAttribute(_to, NO_FEES);
    }

    //Utilities functions for other contracts to calculate fee beforehand
    function checkTransferFee(address _from, address _to, uint256 _value) public view returns (uint) {
        if (hasNoFee(_from, _to)) {
            return 0;
        }
        return _value.mul(transferFeeNumerator).div(transferFeeDenominator);
    }

    function checkMintFee(address _to, uint256 _value) public view returns (uint) {
        if (hasNoFee(address(0), _to)) {
            return 0;
        }
        return _value.mul(mintFeeNumerator).div(mintFeeDenominator).add(mintFeeFlat);
    }

    function checkBurnFee(address _from, uint256 _value) public view returns (uint) {
        if (hasNoFee(_from, address(0))) {
            return 0;
        }
        return _value.mul(burnFeeNumerator).div(burnFeeDenominator).add(burnFeeFlat);
    }


    function changeStakingFees(
        uint256 _transferFeeNumerator,
        uint256 _transferFeeDenominator,
        uint256 _mintFeeNumerator,
        uint256 _mintFeeDenominator,
        uint256 _mintFeeFlat,
        uint256 _burnFeeNumerator,
        uint256 _burnFeeDenominator,
        uint256 _burnFeeFlat) public onlyOwner {
        require(_transferFeeNumerator < _transferFeeDenominator);
        require(_mintFeeNumerator < _mintFeeDenominator);
        require(_burnFeeNumerator < _burnFeeDenominator);
        transferFeeNumerator = _transferFeeNumerator;
        transferFeeDenominator = _transferFeeDenominator;
        mintFeeNumerator = _mintFeeNumerator;
        mintFeeDenominator = _mintFeeDenominator;
        mintFeeFlat = _mintFeeFlat;
        burnFeeNumerator = _burnFeeNumerator;
        burnFeeDenominator = _burnFeeDenominator;
        burnFeeFlat = _burnFeeFlat;
        emit ChangeStakingFees(
            transferFeeNumerator,
            transferFeeDenominator,
            mintFeeNumerator,
            mintFeeDenominator,
            mintFeeFlat,
            burnFeeNumerator,
            burnFeeDenominator,
            burnFeeFlat);
    }

    /**
    * @dev change the address of the staking contract. ie where the staking fee will be sent to
    * @param _newStaker The address to of the new staking contract.
    */
    function changeStaker(address _newStaker) public onlyOwner {
        require(_newStaker != address(0), "new staker cannot be 0x0");
        staker = _newStaker;
        emit ChangeStaker(_newStaker);
    }
}