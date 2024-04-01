import SwapFactory from "../../contracts/SwapFactory.cdc"
import SwapConfig from "../../contracts/SwapConfig.cdc"
import SwapInterfaces from "../../contracts/SwapInterfaces.cdc"

access(all) fun main(userAddr: Address): {Address: UFix64}? {
    var lpTokenCollectionPublicPath = SwapConfig.LpTokenCollectionPublicPath
    let lpTokenCollectionCap = getAccount(userAddr).capabilities.get<&{SwapInterfaces.LpTokenCollectionPublic}>(lpTokenCollectionPublicPath)
    if lpTokenCollectionCap == nil || lpTokenCollectionCap!.check() == false {
        return nil
    }
    let lpTokenCollectionRef = lpTokenCollectionCap!.borrow()!
    let liquidityPairAddrs = lpTokenCollectionRef.getAllLPTokens()
    var res: {Address: UFix64} = {}
    for pairAddr in liquidityPairAddrs {
        var lpTokenAmount = lpTokenCollectionRef.getLpTokenBalance(pairAddr: pairAddr)
        res[pairAddr] = lpTokenAmount
    }
    return res
}