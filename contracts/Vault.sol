// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

//import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Lib} from "./utils/ERC20Lib.sol";

import {IERC4626} from "./interfaces/IERC4626.sol";
import "./utils/SafeERC20.sol";
import "./utils/Math.sol";
//import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import "hardhat/console.sol";

import {IQuickSwapStrategy} from "./interfaces/IQuickSwapStrategy.sol";

/**
 * @dev Implementation of the ERC4626 "Tokenized Vault Standard" as defined in
 * https://eips.ethereum.org/EIPS/eip-4626[EIP-4626].
 *
 * This extension allows the minting and burning of "shares" (represented using the ERC20 inheritance) in exchange for
 * underlying "assets" through standardized {deposit}, {mint}, {redeem} and {burn} workflows. This contract extends
 * the ERC20 standard. Any additional extensions included along it would affect the "shares" token represented by this
 * contract and not the "assets" token which is an independent contract.
 *
 * _Available since v4.7._
 */
contract VaultERC4626 is ERC20Lib, IERC4626 {
    using Math for uint256;
    using SafeERC20 for ERC20Lib;

    IERC20 public _asset;

    mapping(address => uint256) strategydeposits;
    uint256 trackVault;

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    function initialize(IERC20 __asset) public override {
        _asset = __asset;
    }

    /** @dev See {IERC4262-asset} */
    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    /** @dev See {IERC4262-totalAssets} */
    function totalAssets() public view virtual override returns (uint256) {
        //return _asset.balanceOf(address(this));
        return trackVault;
    }

    /** @dev See {IERC4262-convertToShares} */
    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256 shares)
    {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    /** @dev See {IERC4262-convertToAssets} */
    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256 assets)
    {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    /** @dev See {IERC4262-maxDeposit} */
    function maxDeposit(address)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _isVaultCollateralized() ? type(uint256).max : 0;
    }

    /** @dev See {IERC4262-maxMint} */
    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4262-maxWithdraw} */
    function maxWithdraw(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Down);
        //    console.log(strategydeposits[owner]);
        //    return _convertToAssets(strategydeposits[owner], Math.Rounding.Down);
    }

    /** @dev See {IERC4262-maxRedeem} */
    function maxRedeem(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return balanceOf(owner);
        //return strategydeposits[owner];
    }

    /** @dev See {IERC4262-previewDeposit} */
    function previewDeposit(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    /** @dev See {IERC4262-previewMint} */
    function previewMint(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    /** @dev See {IERC4262-previewWithdraw} */
    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToShares(assets, Math.Rounding.Up);
    }

    /** @dev See {IERC4262-previewRedeem} */
    function previewRedeem(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    /** @dev See {IERC4262-deposit} */
    function deposit(
        address strategy,
        uint256 assets,
        address receiver
    ) public virtual override returns (uint256 res) {
        //.log(maxDeposit(receiver));
        require(
            assets <= maxDeposit(receiver),
            "ERC4626: deposit more than max"
        );

        //updatepool 
        res = IQuickSwapStrategy(strategy).deposit(address(_asset), assets);

        uint256 shares = previewDeposit(assets);

        _deposit(msg.sender, receiver, assets, shares);

        bool success1 = IERC20(_asset).approve(strategy, assets);

        //res = IQuickSwapStrategy(strategy).deposit(address(_asset), assets);



    }

    /** @dev See {IERC4262-mint} */
    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        returns (uint256)
    {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        uint256 assets = previewMint(shares);

        _deposit(msg.sender, receiver, assets, shares);

        return assets;
    }

    /** @dev See {IERC4262-withdraw} */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        //console.log("maxwithdrawn", maxWithdraw(owner));
        require(
            assets <= maxWithdraw(owner),
            "ERC4626: withdraw more than max"
        );

        uint256 shares = previewWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    /** @dev See {IERC4262-redeem} */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @dev Internal convertion function (from assets to shares) with support for rounding direction
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amout of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 shares)
    {
        uint256 supply = totalSupply;
        return
            (assets == 0 || supply == 0)
                ? assets.mulDiv(10**decimal, 10**_asset.decimals(), rounding)
                : assets.mulDiv(supply, totalAssets(), rounding);
    }

    /**
     * @dev Internal convertion function (from shares to assets) with support for rounding direction
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256 assets)
    {
        uint256 supply = totalSupply;
        // console.log("total assets", totalAssets());
        // console.log("supply", supply);
        return
            (supply == 0)
                ? shares.mulDiv(10**_asset.decimals(), 10**decimal, rounding)
                : shares.mulDiv(totalAssets(), supply, rounding);
    }

    /**
     * @dev Deposit/mint common workflow
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) private {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transfered and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);

        trackVault += assets;
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) private {
        if (caller != owner) {
            // _spendAllowance(owner, caller, shares);
            uint256 allowed = _allowances[owner][caller]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max && allowed != 0)
                _allowances[owner][msg.sender] = allowed - shares;
        }

        // If _asset is ERC777, `transfer` can trigger trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transfered, which is a valid state.
        _burn(owner, shares);
        SafeERC20.safeTransfer(_asset, receiver, assets);
        trackVault -= assets;

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _isVaultCollateralized() private view returns (bool) {
        return totalAssets() > 0 || totalSupply == 0;
    }

    function deposit_strategy(
        address strategy,
        address _token,
        uint256 _amount
    ) public virtual override returns (uint256 res) {
        require(_amount > 0, "amount is less than zero");

        // bool success = IERC20(_token).approve(address(this),_amount);
        bool success1 = IERC20(_token).approve(strategy, _amount);

        res = IQuickSwapStrategy(strategy).deposit(_token, _amount);
    }

    function withdraw_strategy(
        address strategy,
        address _token,
        uint256 _amount
    ) public virtual override returns (uint256 res) {
        require(_amount > 0, "amount is less than zero");

        bool success1 = IERC20(_token).approve(strategy, _amount);

        res = IQuickSwapStrategy(strategy).withdraw(_token, _amount); // make provistion for withdrwaw fees if needed

        //SafeERC20.safeTransfer(_asset, receiver, _amount);

        // IERC20(_token).transferFrom(strategy,receiver,_amount);   // strategy to receiver or strategy to vault

        IERC20(_token).transferFrom(strategy, address(this), _amount);
    }


    // earn --> updatepool 


}
