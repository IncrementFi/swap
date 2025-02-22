import FungibleToken from "../env/FungibleToken.cdc" // 0xf233dcee88fe0abe

// Token contract of Starly Token (STARLY)
access(all) contract StarlyToken: FungibleToken {
  // Total supply of Flow tokens in existence
  access(all) var totalSupply: UFix64

  // Defines token vault storage path
  access(all) let TokenStoragePath: StoragePath

  // Defines token vault public balance path
  access(all) let TokenPublicBalancePath: PublicPath

  // Defines token vault public receiver path
  access(all) let TokenPublicReceiverPath: PublicPath

  // Event that is emitted when the contract is created
  access(all) event TokensInitialized(initialSupply: UFix64)

  // Event that is emitted when tokens are withdrawn from a Vault
  access(all) event TokensWithdrawn(amount: UFix64, from: Address?)

  // Event that is emitted when tokens are deposited to a Vault
  access(all) event TokensDeposited(amount: UFix64, to: Address?)

  // Event that is emitted when tokens are destroyed
  access(all) event TokensBurned(amount: UFix64)

  // Vault
  //
  // Each user stores an instance of only the Vault in their storage
  // The functions in the Vault and governed by the pre and post conditions
  // in FungibleToken when they are called.
  // The checks happen at runtime whenever a function is called.
  //
  // Resources can only be created in the context of the contract that they
  // are defined in, so there is no way for a malicious user to create Vaults
  // out of thin air.
  //
  access(all) resource Vault: FungibleToken.Vault {

    // holds the balance of a users tokens
    access(all) var balance: UFix64

    // initialize the balance at resource creation time
    init(balance: UFix64) {
      self.balance = balance
    }

    access(contract) fun burnCallback() {
      if self.balance > 0.0 {
        StarlyToken.totalSupply = StarlyToken.totalSupply - self.balance
      }
      self.balance = 0.0
    }

    /// getSupportedVaultTypes optionally returns a list of vault types that this receiver accepts
    access(all) view fun getSupportedVaultTypes(): {Type: Bool} {
      return {self.getType(): true}
    }

    access(all) view fun isSupportedVaultType(type: Type): Bool {
      if (type == self.getType()) { return true } else { return false }
    }

    /// Asks if the amount can be withdrawn from this vault
    access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool {
      return amount <= self.balance
    }

    /// Added simply to conform to FT-V2 interface.
    access(all) view fun getViews(): [Type] { return [] }
    access(all) fun resolveView(_ view: Type): AnyStruct? { return nil }

    // withdraw
    //
    // Function that takes an integer amount as an argument
    // and withdraws that amount from the Vault.
    // It creates a new temporary Vault that is used to hold
    // the money that is being transferred. It returns the newly
    // created Vault to the context that called so it can be deposited
    // elsewhere.
    //
    access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
      self.balance = self.balance - amount
      emit TokensWithdrawn(amount: amount, from: self.owner?.address)
      return <-create Vault(balance: amount)
    }

    // deposit
    //
    // Function that takes a Vault object as an argument and adds
    // its balance to the balance of the owners Vault.
    // It is allowed to destroy the sent Vault because the Vault
    // was a temporary holder of the tokens. The Vault's balance has
    // been consumed and therefore can be destroyed.
    access(all) fun deposit(from: @{FungibleToken.Vault}) {
      let vault <- from as! @StarlyToken.Vault
      self.balance = self.balance + vault.balance
      emit TokensDeposited(amount: vault.balance, to: self.owner?.address)
      vault.balance = 0.0
      destroy vault
    }

    access(all) fun createEmptyVault(): @{FungibleToken.Vault} {
      return <-create Vault(balance: 0.0)
    }
  }

  // createEmptyVault
  //
  // Function that creates a new Vault with a balance of zero
  // and returns it to the calling context. A user must call this function
  // and store the returned Vault in their storage in order to allow their
  // account to be able to receive deposits of this token type.
  //
  access(all) fun createEmptyVault(vaultType: Type): @StarlyToken.Vault {
    return <-create Vault(balance: 0.0)
  }

  /// Added simply to conform to FT-V2 interface.
  access(all) view fun getContractViews(resourceType: Type?): [Type] { return [] }
  access(all) fun resolveContractView(resourceType: Type?, viewType: Type): AnyStruct? { return nil }

  init() {
    // Total supply of STARLY is 100M
    self.totalSupply = 100_000_000.0

    self.TokenStoragePath = /storage/starlyTokenVault
    self.TokenPublicReceiverPath = /public/starlyTokenReceiver
    self.TokenPublicBalancePath = /public/starlyTokenBalance

    // Create the Vault with the total supply of tokens and save it in storage
    let vault <- create Vault(balance: self.totalSupply)
    self.account.storage.save(<-vault, to: self.TokenStoragePath)

    // Create a public capability to the stored Vault that only exposes
    // the `deposit` method through the `Receiver` interface
    let receiverCapability = self.account.capabilities.storage.issue<&{FungibleToken.Receiver}>(self.TokenStoragePath)
    self.account.capabilities.publish(receiverCapability, at: self.TokenPublicReceiverPath)

    // Create a public capability to the stored Vault that only exposes
    // the `balance` field through the `Balance` interface
    let balanceCapability = self.account.capabilities.storage.issue<&{FungibleToken.Balance}>(self.TokenStoragePath)
    self.account.capabilities.publish(balanceCapability, at: self.TokenPublicBalancePath)

    // Emit an event that shows that the contract was initialized
    emit TokensInitialized(initialSupply: self.totalSupply)
  }
}