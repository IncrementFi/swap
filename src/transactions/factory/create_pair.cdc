import FlowToken from "../../contracts/tokens/FlowToken.cdc"
import FungibleToken from "../../contracts/env/FungibleToken.cdc"
import SwapFactory from "../../contracts/SwapFactory.cdc"

/// deploy code copied by a deployed contract
transaction(Token0Name: String, Token0Addr: Address, Token1Name: String, Token1Addr: Address, stableMode: Bool) {
    prepare(userAccount: auth(BorrowValue) &Account) {
        let flowVaultRef = userAccount.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)!
        assert(flowVaultRef.balance >= 0.002, message: "Insufficient balance to create pair, minimum balance requirement: 0.002 flow")
        let accountCreationFeeVault <- flowVaultRef.withdraw(amount: 0.001)
        let token0AddrStr = Token0Addr.toString()
        let token1AddrStr = Token1Addr.toString()
        let token0AddrStr0xTrimmed = token0AddrStr.slice(from: 2, upTo: token0AddrStr.length)
        let token1AddrStr0xTrimmed = token1AddrStr.slice(from: 2, upTo: token1AddrStr.length)
        /// e.g.: "A.1654653399040a61.FlowToken"
        let token0RuntimeType = CompositeType("A.".concat(token0AddrStr0xTrimmed).concat(".").concat(Token0Name)) ?? panic("token0 get runtime type fail")
        let token1RuntimeType = CompositeType("A.".concat(token1AddrStr0xTrimmed).concat(".").concat(Token1Name)) ?? panic("token1 get runtime type fail")
        let token0Vault <- getAccount(Token0Addr).contracts.borrow<&{FungibleToken}>(name: Token0Name)!.createEmptyVault(vaultType: token0RuntimeType)
        let token1Vault <- getAccount(Token1Addr).contracts.borrow<&{FungibleToken}>(name: Token1Name)!.createEmptyVault(vaultType: token1RuntimeType)
        SwapFactory.createPair(token0Vault: <-token0Vault, token1Vault: <-token1Vault, accountCreationFee: <-accountCreationFeeVault, stableMode: stableMode)
    }
}