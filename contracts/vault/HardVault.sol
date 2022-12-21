// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/BlueBerryConst.sol";
import "../utils/BlueBerryErrors.sol";
import "../interfaces/IProtocolConfig.sol";
import "../interfaces/IVault.sol";

contract HardVault is
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev address of underlying token
    IERC20Upgradeable public uToken;
    IProtocolConfig public config;

    event Deposited(
        address indexed account,
        uint256 amount,
        uint256 shareAmount
    );
    event Withdrawn(
        address indexed account,
        uint256 amount,
        uint256 shareAmount
    );

    function initialize(
        IProtocolConfig _config,
        address _uToken,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        if (address(_config) == address(0)) revert ZERO_ADDRESS();
        config = _config;
        uToken = IERC20Upgradeable(_uToken);
    }

    function decimals() public view override returns (uint8) {
        return IERC20MetadataUpgradeable(address(uToken)).decimals();
    }

    /**
     * @notice Deposit underlying assets on Compound and issue share token
     * @param amount Underlying token amount to deposit
     * @return shareAmount cToken amount
     */
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        returns (uint256 shareAmount)
    {
        if (amount == 0) revert ZERO_AMOUNT();
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        uToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        shareAmount = uBalanceAfter - uBalanceBefore;
        _mint(msg.sender, shareAmount);

        emit Deposited(msg.sender, amount, shareAmount);
    }

    /**
     * @notice Withdraw underlying assets from Compound
     * @param shareAmount Amount of cTokens to redeem
     * @return withdrawAmount Amount of underlying assets withdrawn
     */
    function withdraw(uint256 shareAmount)
        external
        override
        nonReentrant
        returns (uint256 withdrawAmount)
    {
        if (shareAmount == 0) revert ZERO_AMOUNT();

        _burn(msg.sender, shareAmount);
        withdrawAmount = shareAmount;

        // Cut withdraw fee if it is in withdrawSafeBoxFee Window (2 months)
        if (
            block.timestamp <
            config.withdrawSafeBoxFeeWindowStartTime() +
                config.withdrawSafeBoxFeeWindow()
        ) {
            uint256 fee = (withdrawAmount * config.withdrawSafeBoxFee()) /
                DENOMINATOR;
            uToken.safeTransfer(config.treasury(), fee);
            withdrawAmount -= fee;
        }
        uToken.safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, shareAmount);
    }
}