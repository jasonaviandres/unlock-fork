// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/**
 * @title The Unlock contract
 * @author Julien Genestoux (unlock-protocol.com)
 * This smart contract has 3 main roles:
 *  1. Distribute discounts to discount token holders
 *  2. Grant dicount tokens to users making referrals and/or publishers granting discounts.
 *  3. Create & deploy Public Lock contracts.
 * In order to achieve these 3 elements, it keeps track of several things such as
 *  a. Deployed locks addresses and balances of discount tokens granted by each lock.
 *  b. The total network product (sum of all key sales, net of discounts)
 *  c. Total of discounts granted
 *  d. Balances of discount tokens, including 'frozen' tokens (which have been used to claim
 * discounts and cannot be used/transferred for a given period)
 *  e. Growth rate of Network Product
 *  f. Growth rate of Discount tokens supply
 * The smart contract has an owner who only can perform the following
 *  - Upgrades
 *  - Change in golden rules (20% of GDP available in discounts, and supply growth rate is at most
 * 50% of GNP growth rate)
 * NOTE: This smart contract is partially implemented for now until enough Locks are deployed and
 * in the wild.
 * The partial implementation includes the following features:
 *  a. Keeping track of deployed locks
 *  b. Keeping track of GNP
 */

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "hardlydifficult-eth/contracts/protocols/Uniswap/IUniswapOracle.sol";
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import "./utils/UnlockOwnable.sol";
import "./utils/UnlockInitializable.sol";
import "./interfaces/IPublicLock.sol";
import "./interfaces/IMintableERC20.sol";
import "./interfaces/IPermit2.sol";

/// @dev Must list the direct base contracts in the order from “most base-like” to “most derived”.
/// https://solidity.readthedocs.io/en/latest/contracts.html#multiple-inheritance-and-linearization
contract Unlock is UnlockInitializable, UnlockOwnable {
  /**
   * The struct for a lock
   * We use deployed to keep track of deployments.
   * This is required because both totalSales and yieldedDiscountTokens are 0 when initialized,
   * which would be the same values when the lock is not set.
   */
  struct LockBalances {
    bool deployed;
    uint totalSales; // This is in wei
    uint yieldedDiscountTokens;
  }

  modifier onlyFromDeployedLock() {
    require(locks[msg.sender].deployed, "ONLY_LOCKS");
    _;
  }

  uint public grossNetworkProduct;

  uint public totalDiscountGranted;

  // We keep track of deployed locks to ensure that callers are all deployed locks.
  mapping(address => LockBalances) public locks;

  // global base token URI
  // Used by locks where the owner has not set a custom base URI.
  string public globalBaseTokenURI;

  // global base token symbol
  // Used by locks where the owner has not set a custom symbol
  string public globalTokenSymbol;

  // The address of the latest public lock template, used by default when `createLock` is called
  address public publicLockAddress;

  // Map token address to oracle contract address if the token is supported
  // Used for GDP calculations
  mapping(address => IUniswapOracle) public uniswapOracles;

  // The WETH token address, used for value calculations
  address public weth;

  // The UDT token address, used to mint tokens on referral
  address public udt;

  // The approx amount of gas required to purchase a key
  uint public estimatedGasForPurchase;

  // Blockchain ID the network id on which this version of Unlock is operating
  uint public chainId;

  // store proxy admin
  address public proxyAdminAddress;
  ProxyAdmin private proxyAdmin;

  // publicLock templates
  mapping(address => uint16) private _publicLockVersions;
  mapping(uint16 => address) private _publicLockImpls;
  uint16 public publicLockLatestVersion;

  // required by Uniswap Universal Router
  address public permit2;

  // Events
  event NewLock(
    address indexed lockOwner,
    address indexed newLockAddress
  );

  event LockUpgraded(address lockAddress, uint16 version);

  event ConfigUnlock(
    address udt,
    address weth,
    uint estimatedGasForPurchase,
    string globalTokenSymbol,
    string globalTokenURI,
    uint chainId
  );

  event SetLockTemplate(address publicLockAddress);

  event GNPChanged(
    uint grossNetworkProduct,
    uint _valueInETH,
    address tokenAddress,
    uint value,
    address lockAddress
  );

  event ResetTrackedValue(
    uint grossNetworkProduct,
    uint totalDiscountGranted
  );

  event UnlockTemplateAdded(
    address indexed impl,
    uint16 indexed version
  );

  event SwapCall(
    address lock,
    address tokenAddress,
    uint amountSpent
  );

  // errors
  error SwapFailed(address uniswapRouter, address tokenIn, address tokenOut, uint amountInMax, bytes callData);
  error LockDoesntExist(address lockAddress);
  error InsufficientBalance();
  error UnauthorizedBalanceChange();
  error LockCallFailed();

  // Use initialize instead of a constructor to support proxies (for upgradeability via OZ).
  function initialize(
    address _unlockOwner
  ) public initializer {
    // We must manually initialize Ownable
    UnlockOwnable.__initializeOwnable(_unlockOwner);
    // add a proxy admin on deployment
    _deployProxyAdmin();
  }

  function initializeProxyAdmin() public onlyOwner {
    require(
      proxyAdminAddress == address(0),
      "ALREADY_DEPLOYED"
    );
    _deployProxyAdmin();
  }

  /**
   * @dev Deploy the ProxyAdmin contract that will manage lock templates upgrades
   * This deploys an instance of ProxyAdmin used by PublicLock transparent proxies.
   */
  function _deployProxyAdmin() private returns (address) {
    proxyAdmin = new ProxyAdmin();
    proxyAdminAddress = address(proxyAdmin);
    return address(proxyAdmin);
  }

  /**
   * @dev Helper to get the version number of a template from his address
   */
  function publicLockVersions(
    address _impl
  ) external view returns (uint16) {
    return _publicLockVersions[_impl];
  }

  /**
   * @dev Helper to get the address of a template based on its version number
   */
  function publicLockImpls(
    uint16 _version
  ) external view returns (address) {
    return _publicLockImpls[_version];
  }

  /**
   * @dev Registers a new PublicLock template immplementation
   * The template is identified by a version number
   * Once registered, the template can be used to upgrade an existing Lock
   */
  function addLockTemplate(
    address impl,
    uint16 version
  ) public onlyOwner {
    _publicLockVersions[impl] = version;
    _publicLockImpls[version] = impl;
    if (publicLockLatestVersion < version)
      publicLockLatestVersion = version;

    emit UnlockTemplateAdded(impl, version);
  }

  /**
   * @notice Create lock (legacy)
   * This deploys a lock for a creator. It also keeps track of the deployed lock.
   * @param _expirationDuration the duration of the lock (pass type(uint).max for unlimited duration)
   * @param _tokenAddress set to the ERC20 token address, or 0 for ETH.
   * @param _keyPrice the price of each key
   * @param _maxNumberOfKeys the maximum nimbers of keys to be edited
   * @param _lockName the name of the lock
   * param _salt [deprec] -- kept only for backwards copatibility
   * This may be implemented as a sequence ID or with RNG. It's used with `create2`
   * to know the lock's address before the transaction is mined.
   * @dev internally call `createUpgradeableLock`
   */
  function createLock(
    uint _expirationDuration,
    address _tokenAddress,
    uint _keyPrice,
    uint _maxNumberOfKeys,
    string calldata _lockName,
    bytes12 // _salt
  ) public returns (address) {
    bytes memory data = abi.encodeWithSignature(
      "initialize(address,uint256,address,uint256,uint256,string)",
      msg.sender,
      _expirationDuration,
      _tokenAddress,
      _keyPrice,
      _maxNumberOfKeys,
      _lockName
    );

    return createUpgradeableLock(data);
  }

  /**
   * @notice Create upgradeable lock
   * This deploys a lock for a creator. It also keeps track of the deployed lock.
   * @param data bytes containing the call to initialize the lock template
   * @dev this call is passed as encoded function - for instance:
   *  bytes memory data = abi.encodeWithSignature(
   *    'initialize(address,uint256,address,uint256,uint256,string)',
   *    msg.sender,
   *    _expirationDuration,
   *    _tokenAddress,
   *    _keyPrice,
   *    _maxNumberOfKeys,
   *    _lockName
   *  );
   * @return address of the create lock
   */
  function createUpgradeableLock(
    bytes memory data
  ) public returns (address) {
    address newLock = createUpgradeableLockAtVersion(
      data,
      publicLockLatestVersion
    );
    return newLock;
  }

  /**
   * Create an upgradeable lock using a specific PublicLock version
   * @param data bytes containing the call to initialize the lock template
   * (refer to createUpgradeableLock for more details)
   * @param _lockVersion the version of the lock to use
   */
  function createUpgradeableLockAtVersion(
    bytes memory data,
    uint16 _lockVersion
  ) public returns (address) {
    require(
      proxyAdminAddress != address(0),
      "MISSING_PROXY_ADMIN"
    );

    // get lock version
    address publicLockImpl = _publicLockImpls[_lockVersion];
    require(
      publicLockImpl != address(0),
      "MISSING_LOCK_TEMPLATE"
    );

    // deploy a proxy pointing to impl
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
        publicLockImpl,
        proxyAdminAddress,
        data
      );
    address payable newLock = payable(address(proxy));

    // assign the new Lock
    locks[newLock] = LockBalances({
      deployed: true,
      totalSales: 0,
      yieldedDiscountTokens: 0
    });

    // trigger event
    emit NewLock(msg.sender, newLock);
    return newLock;
  }

  /**
   * @dev Upgrade a Lock template implementation
   * @param lockAddress the address of the lock to be upgraded
   * @param version the version number of the template
   */
  function upgradeLock(
    address payable lockAddress,
    uint16 version
  ) external returns (address) {
    require(
      proxyAdminAddress != address(0),
      "MISSING_PROXY_ADMIN"
    );

    // check perms
    require(
      _isLockManager(lockAddress, msg.sender) == true,
      "MANAGER_ONLY"
    );

    // check version
    IPublicLock lock = IPublicLock(lockAddress);
    uint16 currentVersion = lock.publicLockVersion();
    require(
      version == currentVersion + 1,
      "VERSION_TOO_HIGH"
    );

    // make our upgrade
    address impl = _publicLockImpls[version];
    require(impl != address(0), "MISSING_TEMPLATE");

    TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(
        lockAddress
      );
    proxyAdmin.upgrade(proxy, impl);

    // let's upgrade the data schema
    // the function is called with empty bytes as migration behaviour is set by the lock in accordance to data version
    lock.migrate("0x");

    emit LockUpgraded(lockAddress, version);
    return lockAddress;
  }

  function _isLockManager(
    address lockAddress,
    address _sender
  ) private view returns (bool isManager) {
    IPublicLock lock = IPublicLock(lockAddress);
    return lock.isLockManager(_sender);
  }

  /**
   * @notice [DEPRECATED] Call to this function has been removed from PublicLock > v9.
   * @dev [DEPRECATED] Kept for backwards compatibility
   */
  function computeAvailableDiscountFor(
    address /* _purchaser */,
    uint /* _keyPrice */
  ) public pure returns (uint discount, uint tokens) {
    return (0, 0);
  }

  /**
   * Helper to get the network mining basefee as introduced in EIP-1559
   * @dev this helper can be wrapped in try/catch statement to avoid
   * revert in networks where EIP-1559 is not implemented
   */
  function networkBaseFee() external view returns (uint) {
    return block.basefee;
  }

  /**
   * This function keeps track of the added GDP, as well as grants of discount tokens
   * to the referrer, if applicable.
   * The number of discount tokens granted is based on the value of the referal,
   * the current growth rate and the lock's discount token distribution rate
   * This function is invoked by a previously deployed lock only.
   * TODO: actually implement
   */
  function recordKeyPurchase(
    uint _value,
    address _referrer
  ) public onlyFromDeployedLock {
    if (_value > 0) {
      uint valueInETH;
      address tokenAddress = IPublicLock(msg.sender)
        .tokenAddress();
      if (
        tokenAddress != address(0) && tokenAddress != weth
      ) {
        // If priced in an ERC-20 token, find the supported uniswap oracle
        IUniswapOracle oracle = uniswapOracles[
          tokenAddress
        ];
        if (address(oracle) != address(0)) {
          valueInETH = oracle.updateAndConsult(
            tokenAddress,
            _value,
            weth
          );
        }
      } else {
        // If priced in ETH (or value is 0), no conversion is required
        valueInETH = _value;
      }

      updateGrossNetworkProduct(
        valueInETH,
        tokenAddress,
        _value,
        msg.sender // lockAddress
      );

      // If GNP does not overflow, the lock totalSales should be safe
      locks[msg.sender].totalSales += valueInETH;

      // Distribute UDT
      if (_referrer != address(0)) {
        IUniswapOracle udtOracle = uniswapOracles[udt];
        if (address(udtOracle) != address(0)) {
          // Get the value of 1 UDT (w/ 18 decimals) in ETH
          uint udtPrice = udtOracle.updateAndConsult(
            udt,
            10 ** 18,
            weth
          );

          uint balance = IMintableERC20(udt).balanceOf(
            address(this)
          );

          // base fee default to 100 GWEI for chains that does
          uint baseFee;
          try this.networkBaseFee() returns (
            uint _basefee
          ) {
            // no assigned value
            if (_basefee == 0) {
              baseFee = 100;
            } else {
              baseFee = _basefee;
            }
          } catch {
            // block.basefee not supported
            baseFee = 100;
          }

          // tokensToDistribute is either == to the gas cost times 1.25 to cover the 20% dev cut
          uint tokensToDistribute = ((estimatedGasForPurchase *
              baseFee) * (125 * 10 ** 18)) /
              100 /
              udtPrice;

          // or tokensToDistribute is capped by network GDP growth
          // we distribute tokens using asymptotic curve between 0 and 0.5
          uint maxTokens = (balance * valueInETH) /
            (2 + (2 * valueInETH) / grossNetworkProduct) /
            grossNetworkProduct;

          // cap to GDP growth!
          if (tokensToDistribute > maxTokens) {
            tokensToDistribute = maxTokens;
          }

          if (tokensToDistribute > 0) {
            // 80% goes to the referrer, 20% to the Unlock dev - round in favor of the referrer
            uint devReward = (tokensToDistribute * 20) / 100;
            
            
            if (balance > tokensToDistribute) {
              // Only distribute if there are enough tokens
              IMintableERC20(udt).transfer(
                _referrer,
                tokensToDistribute - devReward
              );
              IMintableERC20(udt).transfer(
                owner(),
                devReward
              );
            }
          }
        }
      }
    }
  }

  function getBalance(address token) internal view returns (uint) {
    return token == address(0) ?
      address(this).balance 
      :
      IMintableERC20(token).balanceOf(address(this));
  }

  // set permit2 address
  function setPermit2(address _permit2) public onlyOwner {
     permit2 = _permit2;
  }

  /**
   * Please refer to IUnlock.sol for documentation
   */
  function swapAndCall(
    address lock,
    address srcToken,
    uint amountInMax,
    address swapRouter,
    bytes memory swapCalldata,
    bytes memory callData
  ) public payable returns(bytes memory) {
    // check if lock exists
    if(!locks[lock].deployed) {
      revert LockDoesntExist(lock);
    }

    // get lock pricing 
    address destToken = IPublicLock(lock).tokenAddress();

    // get price in destToken from lock
    uint keyPrice = IPublicLock(lock).keyPrice();

    // get balances of Unlock before
    // if payments in ETH, substract the value sent by user to get actual balance
    uint balanceTokenDestBefore = destToken == address(0) ? 
      getBalance(destToken) - msg.value 
            :
      getBalance(destToken);

    uint balanceTokenSrcBefore = 
        srcToken == address(0) ? 
          getBalance(srcToken) - msg.value 
          :
          getBalance(srcToken);

    if(srcToken != address(0)) {
      // Transfer the specified amount of src ERC20 to this contract
      TransferHelper.safeTransferFrom(srcToken, msg.sender, address(this), amountInMax);

      // Approve the router to spend src ERC20
      TransferHelper.safeApprove(srcToken, swapRouter, amountInMax);

      // approve PERMIT2 to manipulate the token
      IERC20(srcToken).approve(permit2, amountInMax);
    }

    // issue PERMIT2 Allowance
    IPermit2(permit2).approve(
      srcToken,
      swapRouter,
      uint160(amountInMax),
      uint48(block.timestamp + 60) // expires after 1min
    );

    // executes the swap
    (bool success, ) = swapRouter.call{ 
      value: srcToken == address(0) ? msg.value : 0 
    }(swapCalldata);

    // make sure to catch Uniswap revert
    if(success == false) {
      revert SwapFailed(swapRouter, srcToken, destToken, amountInMax, swapCalldata);
    }

    // make sure balance is enough to buy key
    if((
      destToken == address(0) ? 
      getBalance(destToken) - msg.value 
            :
      getBalance(destToken)
    ) < balanceTokenDestBefore + keyPrice) {
      revert InsufficientBalance();
    }

    // approve ERC20 to call the lock
    if(destToken != address(0)) {
      IMintableERC20(destToken).approve(lock, keyPrice);
    }

    // call the lock
    (bool lockCallSuccess, bytes memory returnData) = lock.call{
      value: destToken == address(0) ? keyPrice : 0
    }(
      callData
    );

    if(lockCallSuccess == false) {
      revert LockCallFailed();
    }

    // check that Unlock didnt spent more than it received
    if(
      getBalance(srcToken) - balanceTokenSrcBefore < 0
      ||
      getBalance(destToken) - balanceTokenDestBefore < 0
    ) {
      // balance too low
      revert UnauthorizedBalanceChange();
    }

    // returns whatever the lock returned
    return returnData;
  }

  /**
   * Update the GNP by a new value.
   * Emits an event to simply tracking
   */
  function updateGrossNetworkProduct(
    uint _valueInETH,
    address _tokenAddress,
    uint _value,
    address _lock
  ) internal {
    // increase GNP
    grossNetworkProduct = grossNetworkProduct + _valueInETH;

    emit GNPChanged(
      grossNetworkProduct,
      _valueInETH,
      _tokenAddress,
      _value,
      _lock
    );
  }

  /**
   * @notice [DEPRECATED] Call to this function has been removed from PublicLock > v9.
   * @dev [DEPRECATED] only Kept for backwards compatibility
   */
  function recordConsumedDiscount(
    uint /* _discount */,
    uint /* _tokens */
  ) public view onlyFromDeployedLock {
    return;
  }

  // The version number of the current Unlock implementation on this network
  function unlockVersion() external pure returns (uint16) {
    return 11;
  }

  /**
   * @notice Allows the owner to update configuration variables
   */
  function configUnlock(
    address _udt,
    address _weth,
    uint _estimatedGasForPurchase,
    string calldata _symbol,
    string calldata _URI,
    uint _chainId
  ) external onlyOwner {
    udt = _udt;
    weth = _weth;
    estimatedGasForPurchase = _estimatedGasForPurchase;

    globalTokenSymbol = _symbol;
    globalBaseTokenURI = _URI;

    chainId = _chainId;

    emit ConfigUnlock(
      _udt,
      _weth,
      _estimatedGasForPurchase,
      _symbol,
      _URI,
      _chainId
    );
  }

  /**
   * @notice Upgrade the PublicLock template used for future calls to `createLock`.
   * @dev This will initialize the template and revokeOwnership.
   */
  function setLockTemplate(
    address _publicLockAddress
  ) external onlyOwner {
    // First claim the template so that no-one else could
    // this will revert if the template was already initialized.
    IPublicLock(_publicLockAddress).initialize(
      address(this),
      0,
      address(0),
      0,
      0,
      ""
    );
    IPublicLock(_publicLockAddress).renounceLockManager();

    publicLockAddress = _publicLockAddress;

    emit SetLockTemplate(_publicLockAddress);
  }

  /**
   * @notice allows the owner to set the oracle address to use for value conversions
   * setting the _oracleAddress to address(0) removes support for the token
   * @dev This will also call update to ensure at least one datapoint has been recorded.
   */
  function setOracle(
    address _tokenAddress,
    address _oracleAddress
  ) external onlyOwner {
    uniswapOracles[_tokenAddress] = IUniswapOracle(
      _oracleAddress
    );
    if (_oracleAddress != address(0)) {
      IUniswapOracle(_oracleAddress).update(
        _tokenAddress,
        weth
      );
    }
  }

  // Allows the owner to change the value tracking variables as needed.
  function resetTrackedValue(
    uint _grossNetworkProduct,
    uint _totalDiscountGranted
  ) external onlyOwner {
    grossNetworkProduct = _grossNetworkProduct;
    totalDiscountGranted = _totalDiscountGranted;

    emit ResetTrackedValue(
      _grossNetworkProduct,
      _totalDiscountGranted
    );
  }

  /**
   * @dev Redundant with globalBaseTokenURI() for backwards compatibility with v3 & v4 locks.
   */
  function getGlobalBaseTokenURI()
    external
    view
    returns (string memory)
  {
    return globalBaseTokenURI;
  }

  /**
   * @dev Redundant with globalTokenSymbol() for backwards compatibility with v3 & v4 locks.
   */
  function getGlobalTokenSymbol()
    external
    view
    returns (string memory)
  {
    return globalTokenSymbol;
  }

  // required to withdraw WETH
  receive() external payable {}
}
