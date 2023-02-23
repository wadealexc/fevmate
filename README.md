## fevmate

Libraries, mixins, and other Solidity building blocks for use on the Filecoin EVM.

* `access/OwnedClaimable.sol`: Classic Ownable-style access control, implemented using a two-step role transferrance pattern as this should be safer and more likely future-proof in the FEVM.
* `token/`: ERC20, ERC721, and Wrapped FIL contracts, implemented with address normalization for token recipients.
* `proxy/`: Proxy, ProxyAdmin, and Implementation mixins based on ERC1967 and OpenZeppelin's TransparentUpgradeableProxy pattern. These work similarly to their OZ counterparts, except that role transferrance is implemented using the two-step transfer pattern. Additionally, different upgrade validation procedures are used.
* `utils/FilAddress.sol`: Utilities for dealing with all things address. Handles ID addresses and Eth addresses, as well as conversions between the two.
* `utils/CallNative.sol`: Utilities for calling actors via the call_actor precompiles.
* `utils/Signatures.sol`: TODO - signature authorization for multiple signature/account types.

Use at your own risk!

### FEVM Design Pattern - Address Normalization

**Background**

Once created, EOAs and smart contracts have both a standard EVM-style address, as well as an id address, or "actor id." The id is assigned to them when they are first added to the state tree. For contracts, this happens when the constructor is run for the first time, which is triggered by the EAM actor. For EOAs, this happens when they are called for the first time.

Actor ids are just uint64 values, which means they are small enough to fit within Solidity's 20 byte address type. To support interacting with non-EVM actors as if they were EVM-native, the FEVM supports a special format that allows an actor id to be represented using Solidity's address type. Here are two examples:

```solidity
// A Solidity address that contains the id "5" looks like: 
address a = address(0xff00000000000000000000000000000000000005);

// The largest possible actor id (uint64.max) looks like:
address b = address(0xFf0000000000000000000000FFfFFFFfFfFffFfF);
```

... so, the format is a prefix of 0xff, followed by 11 empty bytes, followed by the actor id.

**The Problem**

This works fine for non-EVM actors. Non-EVM actors don't have Eth addresses, meaning the id address is the only address a smart contract needs to talk to non-EVM actors.

On the other hand, EVM-native actors (EOAs and EVM smart contracts) have *both* id addresses and EVM-style addresses. And for FEVM opcodes like `CALL`, `EXTCODESIZE`, etc - either format is accepted and behaves identically. However, EVM-native actors will ALWAYS be in Eth address format when they are `msg.sender`.

To illustrate why this is such a big deal, let's use a simple contract as an example:

```solidity
pragma solidity ^0.8.17;

contract Bank {

    mapping(address => uint) balances;

    // Send a deposit to someone's account
    function deposit(address _account) public payable {
        balances[_account] += msg.value;
    }

    // Withdraw from your own account
    function withdraw() public {
        uint amount = balances[msg.sender];
        balances[msg.sender] = 0;

        msg.sender.call{value: amount}("");
    }
}
```

This Bank contract allows anyone to deposit Fil into someone's account by sending them a `deposit`. The Bank records that the address of the account in question has had their balance raised by the Fil sent to the contract.

A user can withdraw their Fil by calling `withdraw`. Here, the Bank gets the user's balance (`balances[msg.sender]`), sets the balance to zero, and transfers the correct amount via `msg.sender.call`.

Whether `withdraw` is dealing with an Eth address or an id address, the value transfer used here behaves identically. So what's the issue?

Let's say I'm a FEVM user with an Eth-style address: `0xDEADBEEF...11223344`. Because this is the FEVM, I *also* have an actor id - let's say my id is 7. So technically, I have two valid addresses:

* My normal Eth address: `address(0xDEADBEEF...11223344)`
* My id address: `address(0xfF00000000000000000000000000000000000007)`

We've established that the value transfer in `withdraw` will function for both of these addresses. However, note that the account balance being queried is different, depending on the address I use!

`balances[address(0xDEADBEEF...11223344)]` and `balances[address(0xfF00000000000000000000000000000000000007)]` are NOT the same storage slot.

Additionally, when an EVM-native actor calls a contract, the `msg.sender` given by the FEVM will ALWAYS use the EVM-native format.

This means that if someone sends a `deposit` to my id address, when I go to `withdraw`, `msg.sender` will be my Eth address, and it'll look like I don't have a balance!

**The Solution**

Use `FilAddress.normalize` to ensure you're using the EVM-native format whenever possible

TODO
