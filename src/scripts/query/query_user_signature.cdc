
access(all) fun main(userAddr: Address): Bool {
    return getAuthAccount<auth(Storage) &Account>(userAddr).storage.copy<Bool>(from: /storage/incrementFiTerms) ?? false
}