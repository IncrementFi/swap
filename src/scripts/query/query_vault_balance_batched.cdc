import FungibleToken from "../../contracts/env/FungibleToken.cdc"

access(all) fun main(userAddr: Address, vaultPaths: [PublicPath]): [UFix64] {
    var balances: [UFix64] = []
    for vaultPath in vaultPaths {
        let balanceCap = getAccount(userAddr).capabilities.get<&{FungibleToken.Balance}>(vaultPath)
        if balanceCap == nil || balanceCap!.check() == false || balanceCap!.borrow() == nil {
            balances.append(0.0)
        } else {
            balances.append(balanceCap!.borrow()!.balance)
        }
    }
    return balances
}