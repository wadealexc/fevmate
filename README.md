## fevmate

*Libraries, mixins, and other Solidity building blocks for use with Filecoin's FEVM.*

This library borrows heavily from popular security-centric Solidity libraries like [solmate](https://github.com/transmissions11/solmate) and [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts), while including FEVM-specific tweaks to safely support Filecoin-native features.

**Use these libraries at your own risk!** The FEVM is a brand new system and likely has many kinks that will be uncovered by real-world use. FEVM-specific design patterns will emerge over time as things break and are fixed. The contracts provided here are an attempt to safeguard against some of these, but are by no means complete. Do your own research, understand the system you're deploying to, test thoroughly, and above all else - be careful!

This library is in heavy WIP as I extend support and testing for popular Solidity contracts. Note that a big TODO is to add testing for currently-implemented contracts. I've tested a lot of these manually, but am still working on unit testing. Please write your own tests if you end up using any of these.

If you'd like me to consider adding support for your favorite Solidity library, please open an issue! The following contracts are finalized:

**Access**

* [`OwnedClaimable.sol`](./contracts/access/OwnedClaimable.sol): Ownable-style access control, implemented using a two-step role transferrance pattern as this should be safer and more future-proof in the FEVM.

**Tokens**

Standard token contracts, implemented using address normalization for token transfers and approvals, as well as balance and allowance queries.

* [`ERC20.sol`](./contracts/token/ERC20.sol)
* [`ERC721.sol`](./contracts/token/ERC721/ERC721.sol)
* [`WFIL.sol`](./contracts/token/WFIL.sol)

**Utilities**

* [`FilAddress.sol`](./contracts/utils/FilAddress.sol): Utilities for all things related to Solidity's `address` type. Helps implement address normalization, as well as convert between actor ids and evm addresses (and vice-versa).

### Usage

`npm i fevmate`

... then import within your Solidity files! For example:

```solidity
import "fevmate/contracts/utils/FilAddress.sol";

contract YourContract {

    using FilAddress for *;
}
```

### Tests

The FEVM doesn't have a good option for running tests locally against the FEVM. Since the whole point of fevmate is to handle FEVM-specific behavior, it really needs to be fully tested on the FEVM, rather than partially tested with an existing EVM framework.

This is going to remain a big TODO until a suitable test framework exists, but I've started writing basic tests in a forked version of the `ref-fvm` repo. You can find those tests here: [`wadealexc/ref-fvm/solidity-tests`](https://github.com/wadealexc/ref-fvm/tree/387de6febe6d2784c8f4ba538088cda5d8e3ff63/tools/solidity-tests).

These are far from perfect, but at least allow me to test basic behavior. Actually, it seems there were some issues in FilAddress - hence the 1.0.2 release!

### Design Patterns

***This section assumes you have read [BACKGROUND.md](./BACKGROUND.md). If you haven't, please go do that.***

fevmate uses the following patterns:

* *Address normalization*
* *Two-step role transferrance*
* *No hardcoded gas values*

#### Address Normalization

*TL;DR: When in doubt, use [`FilAddress.normalize`](./contracts/utils/FilAddress.sol#L43) on `address` input. If you take nothing else away from this document, please do this!*

As a refresher, both Eth contracts and accounts have both a standard Ethereum address, as well as an id address. The two addresses can be used interchangably for `call`-type operations, as well as for `extcodesize/hash/copy`.

However, when an EVM-type actor calls a contract, `msg.sender` is ALWAYS in the standard Ethereum format.

To illustrate why this is such a big deal, let's use a minimalist ERC20 contract as an example:

```solidity
pragma solidity ^0.8.17;

contract SmolERC20 {

    mapping(address => uint) public balanceOf;

    // Transfer tokens to an account
    function transfer(address _to, uint _amt) public returns (bool) {
        balanceOf[msg.sender] -= _amt;
        balanceOf[_to] += _amt;
        return true;
    }
}
```

Imagine a user with an Eth account is transferred tokens to their ID address. This may not seem like an issue, given that ID addresses behave the same in many situations - the user can give out their ID address to receive FIL, and ID addresses can be used to call Eth contracts and accounts.

However, when the user calls transfer to move their tokens, they appear to have no balance! The contract uses `msg.sender` to look up their balance, which is NOT the ID address to which their tokens were transferred. The ID and Ethereum addresses may be equivalent in many places, but when an EVM-type actor calls an Eth contract, the `msg.sender` will always be their Ethereum address.

One solution to this might be to reject token transfers to ID addresses. However, this prevents use of the contract by non-EVM actors, as BLS and SECPK actors MUST use the ID address format!

---

Instead, contracts should *normalize address input wherever possible.* 

When your contract is given an address (for example, via function parameters), before you do anything with it - check if the address is in the ID format. If it is, try to convert it to a standard Eth format. The FEVM exposes a special precompile for this: `lookup_delegated_address` checks if an actor id has a corresponding f4 address.

If you're not able to perform a conversion, you can use the address as-is; it may belong to a BLS/SECPK or other non-EVM actor.

This library provides [`FilAddress.normalize`](./contracts/utils/FilAddress.sol#L43) as a convenience method for these operations, which performs a conversion if possible, and does nothing otherwise.

---

Here's the same minimalist ERC20 contract, this time using address normalization:

```solidity
pragma solidity ^0.8.17;

import "fevmate/contracts/utils/FilAddress.sol";

contract SmolERC20 {

    using FilAddress for *;
    
    mapping(address => uint) balances;

    // Transfer tokens to an account
    function transfer(address _to, uint _amt) public returns (bool) {
        // Attempt to convert destination to Eth address
        // _to is unchanged if no conversion occurs
        _to = _to.normalize();
        
        balances[msg.sender] -= _amt;
        balances[_to] += _amt;
        return true;
    }
    
    // Balance lookup should also normalize inputs
    function balanceOf(address _a) public view returns (uint) {
        return balances[_a.normalize()];
    }
}
```

In this version, if tokens are transferred to an ID address, the `normalize` method first checks to see if there is a corresponding Eth address. If there is, we use that instead. Otherwise, the address is returned unchanged.

#### Two-step Role Transferrance

Address normalization is one way to ensure Eth contracts and accounts have a canonical format in your smart contracts. 

Another good way is to ignore address formats entirely in favor of requiring the destination address to call into the contract. This isn't efficient or user-friendly enough for things like token transfers, but is a great method to ensure infrequently-performed operations are simple and future-proof.

For example, the classic `Ownable.sol` role transfer pattern looks like this:

```solidity
pragma solidity ^0.8.17;

contract Ownable {
    
    address owner;
    
    function transferOwnership(address _newOwner) public {
        owner = _newOwner;
    }
}
```

Following address normalization, we could just ensure that `_newOwner` is normalized before being assigned to the `owner` variable. And while this should work, it adds unnecessary complexity to a method that needs to function perfectly, the first time, forever.

The primary property address normalization wants to enforce is that every address is resolved to its "`msg.sender` format." In essence, "can this `address` execute smart contract functions?" The downside of `normalize` is that it requires a liberal amount of assembly, and even calls a FEVM precompile to perform an address lookup.

We can answer the same question without all the complexity, by making role transfers a two-step process. A role transfer first designates a "pending" user to receive the role. The transfer is only completed after the "pending" user calls the corresponding "accept" method. 

Address format isn't checked anywhere, but by ensuring the pending user can call the "accept" function, we know the address is in its "`msg.sender` format." Also, the huge decrease in complexity means this method should remain compatible with any future Filecoin network upgrade!

This library provides [`OwnedClaimable.sol`](./contracts/access/OwnedClaimable.sol) as a mixin to help implement two-step role transfers.

#### No hardcoded gas values

When porting smart contracts to the FEVM, make sure that:

* The code does NOT hardcode gas values anywhere.
* The code does NOT use Solidity's `address.send` or `address.transfer`
* The code does NOT rely on the `INVALID` opcode or precompile gas restriction described in [BACKGROUND.md](./BACKGROUND.md).

In all cases, you should forward ALL gas to the callee. If you need reentrancy protection, use a `ReentrancyGuard` like the ones provided by [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol) or [solmate](https://github.com/transmissions11/solmate/blob/main/src/utils/ReentrancyGuard.sol).
