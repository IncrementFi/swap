import SwapFactory from "../../contracts/SwapFactory.cdc"

transaction() {
    prepare(userAccount: auth(BorrowValue) &Account) {
        let factoryAdminRef = userAccount.storage.borrow<&SwapFactory.Admin>(from: /storage/swapFactoryAdmin)!
        factoryAdminRef.togglePermissionless()
    }
}