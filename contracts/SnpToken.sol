// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/ISnpToken.sol";

contract SnpToken is ISnpToken, Ownable, Pausable {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) public minters;

    uint256 private _totalSupply;

    string private _name = "SNP Token";
    string private _symbol = "SNP";
    uint8 private _decimals = 18;
    uint256 public TOTAL_SUPPLY = 3000000 ether;

    constructor() public {
        _totalSupply = 0;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public override view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public override view returns (uint256) {
        return _balances[account];
    }

    function addMinter(address _minter) external onlyOwner {
        minters[_minter] = true;
    }

    function removeMinter(address _minter) external onlyOwner {
        minters[_minter] = false;
    }

    function mint(address account, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        require(minters[msg.sender], "SnpToken: You are not the minter");
        uint256 supply = _totalSupply.add(amount);
        if (supply > TOTAL_SUPPLY) {
            supply = TOTAL_SUPPLY;
        }
        amount = supply.sub(_totalSupply);
        _mint(account, amount);
        return amount;
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override whenNotPaused returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender].sub(
                amount,
                "SnpToken: TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE"
            )
        );
        return true;
    }

    function allowance(address owner, address spender)
        public
        virtual
        override
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(
                subtractedValue,
                "SnpToken: DECREASED_ALLOWANCE_BELOW_ZERO"
            )
        );
        return true;
    }

    function burn(uint256 amount)
        public
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        _burn(msg.sender, amount);
        return true;
    }

    function withdraw(address token, uint256 amount) public onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(
            sender != address(0),
            "SnpToken: TRANSFER_FROM_THE_ZERO_ADDRESS"
        );
        require(
            recipient != address(0),
            "SnpToken: TRANSFER_TO_THE_ZERO_ADDRESS"
        );

        _balances[sender] = _balances[sender].sub(
            amount,
            "SnpToken: TRANSFER_AMOUNT_EXCEEDS_BALANCE"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "SnpToken: APPROVE_FROM_THE_ZERO_ADDRESS");
        require(spender != address(0), "SnpToken: APPROVE_TO_THE_ZERO_ADDRESS");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "SnpToken: mint to the zero address");
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "SnpToken: BURN_FROM_THE_ZERO_ADDRESS");
        _balances[account] = _balances[account].sub(
            amount,
            "SnpToken: BURN_AMOUNT_EXCEEDS_BALANCE"
        );
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }
}
