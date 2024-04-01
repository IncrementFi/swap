import FungibleToken from "../../contracts/env/FungibleToken.cdc"
import SwapFactory from "../../contracts/SwapFactory.cdc"
import SwapInterfaces from "../../contracts/SwapInterfaces.cdc"
import SwapConfig from "../../contracts/SwapConfig.cdc"

transaction(
    pairAddr: Address,
    lpTokenAmount: UFix64,
    toAddr: Address
) {
    prepare(userAccount: auth(BorrowValue) &Account) {
        let lpTokenCollectionFrom = userAccount.storage.borrow<&SwapFactory.LpTokenCollection>(from: SwapConfig.LpTokenCollectionStoragePath)
            ?? panic("Cannot borrow reference to LpTokenCollection")
        let lpTokenCollectionTo = getAccount(toAddr).capabilities.borrow<&{SwapInterfaces.LpTokenCollectionPublic}>(SwapConfig.LpTokenCollectionPublicPath)
            ?? panic("Cannot borrow reference to tansfer target user's LpTokenCollection")

        let lpTokenTransfer <- lpTokenCollectionFrom.withdraw(pairAddr: pairAddr, amount: lpTokenAmount)
        lpTokenCollectionTo.deposit(pairAddr: pairAddr, lpTokenVault: <- lpTokenTransfer)
    }
}