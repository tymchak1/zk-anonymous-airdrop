// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;
import {IERC20} from "../../src/interfaces/IERC20.sol";

contract ERC20Mock is IERC20 {
    string public name = "ERC20Mock";
    string public symbol = "E20M";
    uint8 public decimals = 18;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balanceOf[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowance[owner][spender];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        require(_balanceOf[msg.sender] >= value, "ERC20: transfer amount exceeds balance");
        _balanceOf[msg.sender] -= value;
        _balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        require(_balanceOf[from] >= value, "ERC20: transfer amount exceeds balance");
        require(_allowance[from][msg.sender] >= value, "ERC20: transfer amount exceeds allowance");
        _balanceOf[from] -= value;
        _balanceOf[to] += value;
        _allowance[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }

    function mint(address account, uint256 amount) external override {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _balanceOf[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(account != address(0), "ERC20: burn from the zero address");
        require(_balanceOf[account] >= amount, "ERC20: burn amount exceeds balance");
        _balanceOf[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }
}
