## fevmate

Libraries, mixins, and other Solidity building blocks for use on the Filecoin EVM.

* `access/Ownable.sol`: Classic Ownable-style access control, implemented using a two-step role transferrance pattern as this should be safer and more likely future-proof in the FEVM.
* `token/`: ERC20, ERC721, and Wrapped FIL contracts, implemented with address normalization for token recipients.
* `utils/Address.sol`: Utilities for dealing with all things address. Handles ID addresses and Eth addresses, as well as conversions between the two.

Use at your own risk!
