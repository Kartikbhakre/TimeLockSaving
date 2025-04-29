// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TimeLockSavings
 * @dev A contract that allows users to deposit funds that cannot be withdrawn until a predetermined time
 */
contract TimeLockSavings {
    // Structure to track individual savings accounts
    struct SavingsAccount {
        uint256 balance;         // Current balance in wei
        uint256 unlockTimestamp; // Timestamp when funds can be withdrawn
        uint256 depositDate;     // When the deposit was made
        uint256 savingsGoal;     // Optional savings goal
        string savingsPurpose;   // Optional purpose for saving
    }
    
    // Mapping from user address to their savings account
    mapping(address => SavingsAccount) public accounts;
    
    // Total funds locked in the contract
    uint256 public totalLockedFunds;
    
    // Minimum lock period in seconds (default: 30 days)
    uint256 public minimumLockPeriod = 30 days;
    
    // Optional interest rate in basis points (e.g., 500 = 5%)
    uint256 public interestRateBasisPoints = 0;
    
    // Owner of the contract
    address public owner;
    
    // Events
    event Deposit(address indexed user, uint256 amount, uint256 unlockTimestamp);
    event Withdrawal(address indexed user, uint256 amount);
    event InterestRateChanged(uint256 oldRate, uint256 newRate);
    event MinimumLockPeriodChanged(uint256 oldPeriod, uint256 newPeriod);
    event SavingsGoalSet(address indexed user, uint256 goal, string purpose);
    
    /**
     * @dev Constructor to initialize the contract
     * @param _minimumLockPeriod Minimum lock period in seconds
     * @param _interestRateBasisPoints Optional interest rate in basis points
     */
    constructor(uint256 _minimumLockPeriod, uint256 _interestRateBasisPoints) {
        owner = msg.sender;
        
        if (_minimumLockPeriod > 0) {
            minimumLockPeriod = _minimumLockPeriod;
        }
        
        interestRateBasisPoints = _interestRateBasisPoints;
    }
    
    /**
     * @dev Modifier to ensure only the owner can call certain functions
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    /**
     * @dev Allows a user to deposit funds and lock them for a specified time
     * @param _lockPeriod The period in seconds that the funds will be locked
     * @param _savingsGoal Optional savings goal amount
     * @param _purpose Optional purpose for saving
     */
    function deposit(uint256 _lockPeriod, uint256 _savingsGoal, string memory _purpose) external payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        require(_lockPeriod >= minimumLockPeriod, "Lock period must be at least the minimum lock period");
        
        uint256 unlockTime = block.timestamp + _lockPeriod;
        
        // Initialize or update the savings account
        SavingsAccount storage account = accounts[msg.sender];
        
        // If there's an existing account, update it
        if (account.balance > 0) {
            // Calculate weighted average unlock time if there are existing funds
            uint256 currentBalance = account.balance;
            uint256 currentUnlockTime = account.unlockTimestamp;
            uint256 newTotalBalance = currentBalance + msg.value;
            
            // Calculate weighted average unlock time
            uint256 weightedUnlockTime = ((currentBalance * currentUnlockTime) + 
                                        (msg.value * unlockTime)) / newTotalBalance;
            
            account.unlockTimestamp = weightedUnlockTime;
            account.balance += msg.value;
        } else {
            // Create a new account
            account.balance = msg.value;
            account.unlockTimestamp = unlockTime;
            account.depositDate = block.timestamp;
        }
        
        // Set savings goal and purpose if provided
        if (_savingsGoal > 0) {
            account.savingsGoal = _savingsGoal;
            account.savingsPurpose = _purpose;
            emit SavingsGoalSet(msg.sender, _savingsGoal, _purpose);
        }
        
        // Update total locked funds
        totalLockedFunds += msg.value;
        
        emit Deposit(msg.sender, msg.value, account.unlockTimestamp);
    }
    
    /**
     * @dev Allows a user to withdraw their funds after the lock period
     * @return The amount withdrawn
     */
    function withdraw() external returns (uint256) {
        SavingsAccount storage account = accounts[msg.sender];
        
        require(account.balance > 0, "No funds available to withdraw");
        require(block.timestamp >= account.unlockTimestamp, "Funds are still locked");
        
        uint256 amount = account.balance;
        
        // Calculate interest if applicable
        if (interestRateBasisPoints > 0) {
            uint256 timeLockedInSeconds = block.timestamp - account.depositDate;
            uint256 timeLockedInDays = timeLockedInSeconds / 1 days;
            
            // Calculate daily interest rate (basis points / 10000 / 365)
            uint256 dailyInterestRate = interestRateBasisPoints / 10000 / 365;
            
            // Calculate interest amount
            uint256 interestAmount = (amount * dailyInterestRate * timeLockedInDays) / 100;
            amount += interestAmount;
        }
        
        // Reset account
        account.balance = 0;
        account.unlockTimestamp = 0;
        account.depositDate = 0;
        account.savingsGoal = 0;
        account.savingsPurpose = "";
        
        // Update total locked funds
        totalLockedFunds -= amount;
        
        // Transfer funds to user
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawal(msg.sender, amount);
        
        return amount;
    }
    
    /**
     * @dev Returns the current balance, unlock time, and time remaining for a user's savings account
     * @return balance The current balance
     * @return unlockTimestamp The timestamp when funds can be withdrawn
     * @return timeRemaining The time remaining in seconds before funds can be withdrawn
     * @return savingsGoal The savings goal amount
     * @return savingsPurpose The purpose for saving
     */
    function getAccountInfo() external view returns (
        uint256 balance,
        uint256 unlockTimestamp,
        uint256 timeRemaining,
        uint256 savingsGoal,
        string memory savingsPurpose
    ) {
        SavingsAccount storage account = accounts[msg.sender];
        
        balance = account.balance;
        unlockTimestamp = account.unlockTimestamp;
        
        if (account.unlockTimestamp > block.timestamp) {
            timeRemaining = account.unlockTimestamp - block.timestamp;
        } else {
            timeRemaining = 0;
        }
        
        savingsGoal = account.savingsGoal;
        savingsPurpose = account.savingsPurpose;
    }
    
    /**
     * @dev Sets a new interest rate (only owner)
     * @param _newInterestRateBasisPoints New interest rate in basis points
     */
    function setInterestRate(uint256 _newInterestRateBasisPoints) external onlyOwner {
        uint256 oldRate = interestRateBasisPoints;
        interestRateBasisPoints = _newInterestRateBasisPoints;
        emit InterestRateChanged(oldRate, _newInterestRateBasisPoints);
    }
    
    /**
     * @dev Sets a new minimum lock period (only owner)
     * @param _newMinimumLockPeriod New minimum lock period in seconds
     */
    function setMinimumLockPeriod(uint256 _newMinimumLockPeriod) external onlyOwner {
        require(_newMinimumLockPeriod > 0, "Minimum lock period must be greater than 0");
        uint256 oldPeriod = minimumLockPeriod;
        minimumLockPeriod = _newMinimumLockPeriod;
        emit MinimumLockPeriodChanged(oldPeriod, _newMinimumLockPeriod);
    }
    
    /**
     * @dev Allows a user to check if their funds are available for withdrawal
     * @return boolean indicating if funds are available
     */
    function isWithdrawalAvailable() external view returns (bool) {
        SavingsAccount storage account = accounts[msg.sender];
        return account.balance > 0 && block.timestamp >= account.unlockTimestamp;
    }
    
    /**
     * @dev Allows a user to extend their lock period
     * @param _additionalLockPeriod Additional time to lock funds in seconds
     */
    function extendLockPeriod(uint256 _additionalLockPeriod) external {
        require(_additionalLockPeriod > 0, "Additional lock period must be greater than 0");
        
        SavingsAccount storage account = accounts[msg.sender];
        require(account.balance > 0, "No funds available to extend lock");
        
        // Extend lock period
        account.unlockTimestamp += _additionalLockPeriod;
        
        emit Deposit(msg.sender, 0, account.unlockTimestamp);
    }
    
    /**
     * @dev Emergency withdrawal function with penalty (for demonstration purposes)
     * @param _penaltyPercentage Percentage of funds to be penalized (1-100)
     */
    function emergencyWithdraw(uint256 _penaltyPercentage) external {
        require(_penaltyPercentage >= 1 && _penaltyPercentage <= 100, "Penalty percentage must be between 1 and 100");
        
        SavingsAccount storage account = accounts[msg.sender];
        require(account.balance > 0, "No funds available to withdraw");
        
        uint256 amount = account.balance;
        uint256 penalty = (amount * _penaltyPercentage) / 100;
        uint256 amountToWithdraw = amount - penalty;
        
        // Reset account
        account.balance = 0;
        account.unlockTimestamp = 0;
        account.depositDate = 0;
        account.savingsGoal = 0;
        account.savingsPurpose = "";
        
        // Update total locked funds
        totalLockedFunds -= amount;
        
        // Transfer penalty to contract owner
        (bool successPenalty, ) = payable(owner).call{value: penalty}("");
        require(successPenalty, "Penalty transfer failed");
        
        // Transfer remaining funds to user
        (bool successWithdraw, ) = payable(msg.sender).call{value: amountToWithdraw}("");
        require(successWithdraw, "Withdrawal transfer failed");
        
        emit Withdrawal(msg.sender, amountToWithdraw);
    }
}
