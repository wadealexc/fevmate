## fevmate

*Libraries, mixins, and other Solidity building blocks for use with Filecoin's FEVM.*

This library borrows heavily from popular security-centric Solidity libraries like [solmate](https://github.com/transmissions11/solmate) and [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts), while including FEVM-specific tweaks to safely support Filecoin-native features.

**Use these libraries at your own risk!** The FEVM is a brand new system and likely has many kinks that will be uncovered by real-world use. FEVM-specific design patterns will emerge over time as things break and are fixed. The contracts provided here are an attempt to safeguard against some of these, but are by no means complete. Do your own research, understand the system you're deploying to, test thoroughly, and above all else - be careful!

fevmate supports the following design patterns, which you can read more about below:
* Address normalization
* Two-step role transferrance
* No hardcoded gas values

This library is still WIP as I extend support for popular Solidity contracts. If you'd like me to consider adding support for your favorite Solidity library, please open an issue! The following libraries are finalized:

**Access**

* [`OwnedClaimable.sol`](./contracts/access/OwnedClaimable.sol): Ownable-style access control, implemented using a two-step role transferrance pattern as this should be safer and more future-proof in the FEVM.

**Tokens**

Standard token contracts, implemented using address normalization for token transfers and approvals, as well as balance and allowance queries.

* [`ERC20.sol`](./contracts/token/ERC20.sol)
* [`ERC721.sol`](./contracts/token/ERC721/ERC721.sol)
* [`WFIL.sol`](./contracts/token/WFIL.sol)

**Utilities**

* [`FilAddress.sol`](./contracts/utils/FilAddress.sol): Utilities for all things related to Solidity's `address` type. Helps implement address normalization, as well as convert between actor ids and evm addresses (and vice-versa).
* [`CallNative.sol`](./contracts/utils/CallNative.sol): Helper methods used to call actors via FEVM's `call_actor_id` precompile.

### Design Patterns

This section describes the rationale behind the design patterns used by fevmate:

* *Address normalization:* Ensure `address` types are normalized to an evm-native format, if possible, while still supporting other Filecoin-native actor types. Among other problems, this should prevent issues where Ethereum accounts and smart contracts are not able to access assets transferred to them via actor id.
* *Two-step role transferrance:* Role transfers are implemented by first designating a "pending" user to receive the role. The transfer is only completed after the "pending" user calls the corresponding "accept" method. This ensures role transfers are only made to accounts with the capability to invoke Ethereum smart contracts.
* *No hardcoded gas values:* Avoid using hardcoded gas values in function calls, and avoid Solidity's `address.send` and `address.transfer` methods.

Read on for a detailed explanation of each of of these.

#### Background Info

The FEVM extends Filecoin's FVM to support Ethereum-style accounts and smart contracts. For the most part, the FEVM and EVM are very similar. However, there are a few key differences one should consider before blindly redeploying EVM-native smart contracts to Filecoin.

**1. The FEVM does not exist in isolation.** On Ethereum, smart contracts and EOAs only ever call (or are called by) other smart contracts and EOAs. In the FEVM, smart contracts and EOAs can interact with other Filecoin-native actors. 

FEVM smart contracts must support these other actor types in order to be fully compatible, as well as to avoid unintended issues.

**2. Filecoin has multiple addressing schemes.** With the addition of the FEVM, Filecoin has 5 different native address types:

* *f0 - ID address*: On creation, actors are assigned a sequential `uint64` actor id. Every actor (including Ethereum accounts and smart contracts) will have an actor id.
* *f1 - SECP256K1 address*: 20 byte pubkey hashes that correspond to SECP256K1 EOAs.
* *f2 - Actor address*: 20 byte hashes used as a "reorg-safe" address scheme. All actors have an f2 address.
* *f3 - BLS address*: 48 byte pubkeys that correspond to BLS EOAs.
* *f4 - Delegated address*: An extensible addressing format that is currently only used by Ethereum EOAs and smart contracts. See [FIP-0048](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0048.md) and [FIP-0055](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0055.md) for more info.

FEVM smart contracts must be able to address actors using nonstandard EVM addresses, and should be designed in a way that accounts for nonstandard EVM addresses.

**3. FEVM execution gas is completely different than EVM gas.** The FEVM is embedded into a larger wasm runtime, which supports running code from other Filecoin-native actors. Each Filecoin actor (including the EVM interpreter) is written in rust, compiled to wasm bytecode. This bytecode is injected with gas metering that allows the Filecoin runtime to consume execution gas as the wasm executes.

Rather than come up with a conversion between the EVM's gas-per-instruction and Filecoin's metered wasm, the FEVM has abandoned the EVM's gas semantics in favor of using the existing metered wasm to handle execution gas. As a result, the numerical values required for FEVM execution will look very different from EVM gas values.

#### Address Normalization

Once created, EOAs and smart contracts have both a standard EVM-style address, as well as an id address, or "actor id." The id is assigned to them when they are first added to the state tree. For contracts, this happens when the constructor is run for the first time, which is triggered by the EAM actor. For EOAs, this happens when they are called for the first time.

Actor ids are just uint64 values, which means they are small enough to fit within Solidity's 20 byte address type. To support interacting with non-EVM actors as if they were EVM-native, the FEVM supports a special format that allows an actor id to be represented using Solidity's address type. Here are two examples:

```solidity
// A Solidity address that contains the id "5" looks like: 
address a = address(0xff00000000000000000000000000000000000005);

// The largest possible actor id (uint64.max) looks like:
address b = address(0xFf0000000000000000000000FFfFFFFfFfFffFfF);
```

... so, the format is a prefix of 0xff, followed by 11 empty bytes, followed by the actor id.

*The Problem*

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

*The Solution*

Use `FilAddress.normalize` to ensure you're using the EVM-native format whenever possible

TODO

#### Two-step Role Transferrance

TODO

#### No hardcoded gas values

TODO
