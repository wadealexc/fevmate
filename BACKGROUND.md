## Background Info

The FEVM extends Filecoin's FVM to support Ethereum-style accounts and smart contracts. For the most part, the FEVM and EVM are very similar. However, there are a few key differences one should consider before blindly redeploying EVM-native smart contracts to Filecoin. This section details crucial background information about the FEVM to keep in mind when deploying to Filecoin.

First, a quick glossary. I will use the following terms:

***Actors*** are blocks of Rust code compiled to wasm bytecode. These exist at distinct addresses in Filecoin, and carry out certain functions.

When you deploy a Solidity smart contract to Filecoin, the FVM deploys a new EVM actor for you, assigns it a new address, and stores the EVM bytecode in the EVM actor's state. Like all actors, the EVM actor is written in rust, and contains an implementation of an EVM interpreter. Basically, it runs the contract's bytecode when invoked.

***EVM-type actor*** will refer to actors that have counterparts on Ethereum. Specifically:

* ***Eth contract*** will refer to a smart contract deployed to Filecoin. Again, these are represented internally as "EVM actors," but for sanity's sake I'm going to call them Eth contracts.
* ***Eth account*** will refer to an Ethereum EOA account. These are directly analogous to Ethereum's EOAs and have very similar properties.

***Filecoin-native actor*** or ***non-EVM actor*** will refer to actors that do not exist in Ethereum. This can refer to EOAs like BLS/SECPK actors, as well as builtin contract-like actors like the Miner, Multisig, and Market actors.

---

### 1. Gas

FEVM execution gas is completely different than EVM gas. The FEVM is embedded into a larger wasm runtime, which supports running code from both EVM-type actors, as well as Filecoin-native actors. All actors (including EVM-type actors) are written in rust, compiled to wasm bytecode. This bytecode is injected with gas metering that allows the Filecoin runtime to consume execution gas as the wasm executes.

Rather than come up with a conversion between the EVM's gas-per-instruction and Filecoin's metered wasm, the FEVM has abandoned the EVM's gas semantics in favor of using the existing metered wasm to handle execution gas. As a result, the numerical values required for FEVM execution will look very different from EVM gas values.

Additional quirks of FEVM gas:

* The gas required to execute an Eth contract depends in small part on its bytecode size, as the first operation performed is to load the bytecode from state.
* The `INVALID` opcode does NOT consume all available gas as it does in Ethereum. In the FEVM, it behaves identically to `REVERT`, except that it cannot return data.
* When calling precompiles, the passed in gas value is ignored. Execution will not consume more gas than you have available, but it is NOT possible to restrict the gas consumed by a precompile.

### 2. Addresses

The FEVM does not exist in isolation. On Ethereum, smart contracts and EOAs only ever call (or are called by) other smart contracts and EOAs. In the FEVM, Eth contracts and accounts can interact with each other, but they can also interact with Filecoin-native actors.

Eth contracts must support these other actor types in order to be fully compatible, as well as to avoid unintended issues. The most important information to understand is that Filecoin has multiple address types. With the addition of the FEVM, Filecoin has 5 different native address types:

* *f0 - ID address*: On creation, actors are assigned a sequential `uint64` actor id. Every actor (including Eth contracts and accounts) will have an actor id.
* *f1 - SECP256K1 address*: 20 byte pubkey hashes that correspond to SECP256K1 EOAs.
* *f2 - Actor address*: 20 byte hashes used as a "reorg-safe" address scheme. All actors have an f2 address.
* *f3 - BLS address*: 48 byte pubkeys that correspond to BLS EOAs.
* *f4 - Delegated address*: An extensible addressing format that is currently only used by Eth contracts and accounts. See [FIP-0048](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0048.md) and [FIP-0055](https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0055.md) for more info. The f4 format will likely be expanded in future upgrades to incorporate other actor types.

For the most part, Filecoin's native actors can be referenced by their actor id (f0 address). Actor ids are just `uint64` values, which means they are small enough to fit within Solidity's 20-byte `address` type. To provide support for non-EVM actors as first-class citizens, the FEVM recognizes a special format for ID addresses that fits into the 20-byte Solidity `address` type.

The format is `0xff`, followed by 11 empty bytes, followed by the `uint64` actor id. Here are two examples:

```solidity
// A Solidity address that contains the id "5" looks like: 
address constant ID_ADDRESS_FIVE = 0xff00000000000000000000000000000000000005;
// The largest possible actor id (uint64.max) looks like:
address constant MAX_ID_ADDRESS = 0xFf0000000000000000000000FFfFFFFfFfFffFfF;
```

For the most part, you can use ID addresses to refer to non-EVM actors. **However, ALWAYS keep in mind** that Eth contracts and accounts have BOTH a standard Ethereum address, AND an ID address. The following details the behavior of various EVM operations in relation to these different actors and address formats.

#### Calling other actors

1. *Eth contract calls an EVM-type actor*: BOTH the Ethereum-style address and ID address function the exact same way. i.e. whether your contract is calling an Eth contract or Eth account, the address format used doesn't matter. Here's an example:

```solidity
using FilAddress for *;

interface ERC20 {
    function transfer(address, uint) public returns (bool);
}

address constant SOME_ETH_CONTRACT = address(0xc6e2459991BfE27cca6d86722F35da23A1E4Cb97);

// Call ERC20.transfer on the Eth contract
function doCallA() public {  
    ERC20(SOME_ETH_CONTRACT).transfer(msg.sender, 100);
}

// Call ERC20.transfer on the Eth contract, except target its id address
// Note that the call is performed identically! Under the hood, the runtime
// is converting the Eth format to its ID equivalent before calling, anyway.
// ... so, we can use either.
function doCallB() public {
    // Get the ID address equivalent
    (bool success, uint64 actorID) = SOME_ETH_CONTRACT.getActorID();
    require(success);
    address contractIDAddr = actorID.toIDAddress();
    
    // Call ERC20.transfer - works the same as in doCallA!
    ERC20(contractIDAddr).transfer(msg.sender, 100);
}
```

2. *Eth contract calls a BLS/SECPK actor*: Use the ID address. These behave pretty much like an Eth account. Calls to these actors will always succeed (assuming sufficient gas, balance, stack depth, etc).

```solidity
address constant SOME_ETH_ACCOUNT = address(0xc6e2459991BfE27cca6d86722F35da23A1E4Cb97);
// The ID address of some BLS actor
address constant SOME_BLS_ACCOUNT = address(0xff000000000000000000000000000000BEEFBEEF);

// Call the Eth account and transfer some funds
function doCallA() public {
    SOME_ETH_ACCOUNT.call{value: 100}("");
}

// Call the BLS account and transfer some funds
function doCallB() public {
    SOME_BLS_ACCOUNT.call{value: 100}("");
}
```

3. *Eth contract calls another Filecoin-native actor*: Use the ID address. However, note that a plain call will only work for some actor types. Many actors (like the Miner actor) export methods that can be called by Eth contracts through a special FEVM precompile (either the `call_actor` or `call_actor_id` precompile). This library doesn't handle the specific interfaces these actors export. Take a look at [`Zondax/filecoin-solidity`](https://github.com/Zondax/filecoin-solidity/) if your contract needs to call native actor methods.

#### Getting called by other actors (aka "who is `msg.sender`?")

`msg.sender` will either be an ID address, or the standard Ethereum address format. You can use this information to help determine what actor type is calling your contract:

* If `msg.sender` is in the standard Ethereum address format, you were called by an EVM-type actor (i.e. an Eth contract or account)
* If `msg.sender` is an ID address, you were called by a non-EVM actor (i.e. some other Filecoin-native actor).

#### Getting information about other actors

* Eth contracts should have the same `EXTCODESIZE`, `EXTCODEHASH`, and `EXTCODECOPY` values as they do in Ethereum. Note, too, that you can check these with either the Ethereum address OR ID address. They behave the same.
* Account-type actors (BLS, SECP, and Eth account actors) have:
    * `EXTCODESIZE == 0`
    * `EXTCODEHASH == keccak256("")`
    * `EXTCODECOPY` will copy zeroes
* Nonexistent actors have:
    * `EXTCODESIZE == 0`
    * `EXTCODEHASH == 0`
    * `EXTCODECOPY` will copy zeroes
* Other non-EVM actors have:
    * `EXTCODESIZE == 1`
    * `EXTCODEHASH == keccak256(abi.encodePacked(0xFE))`
    * `EXTCODECOPY` will copy 0xFE, then zeroes.
