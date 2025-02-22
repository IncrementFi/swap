/**

# Factory contract for creating new trading pairs.

# Author: Increment Labs

*/
import FungibleToken from "./env/FungibleToken.cdc"
import SwapError from "./SwapError.cdc"
import SwapConfig from "./SwapConfig.cdc"
import SwapInterfaces from "./SwapInterfaces.cdc"
import StableSwapFactory from "./StableSwapFactory.cdc"

access(all) contract SwapFactory {
    /// Account which has deployed pair template contract
    access(all) var pairContractTemplateAddress: Address

    /// All pairs' address array
    access(self) let pairs: [Address]
    /// pairMap[token0Identifier][token1Identifier] == pairMap[token1Identifier][token0Identifier]
    access(self) let pairMap: { String: {String: Address} }

    /// Flag indicating weighted keys to be attached when deploying pair contracts for the sake of upgradability & safety reasons.
    /// Now the flag is set but will be nullified in future once Stable Cadence is out and ready for a pure decentralized exchange.
    access(all) var pairAccountPublicKey: String?

    /// Fee receiver address
    access(all) var feeTo: Address?

    /// Reserved parameter fields: {ParamName: Value}
    /// Used fields:
    ///   |__ 1. "flashloanRateBps" -> UInt64
    ///   |__ 2. "volatileRateBps" -> UInt64
    ///   |__ 3. "stableRateBps" -> UInt64
    ///   |__ 4. "protocolFeeCut" -> UFix64
    access(self) let _reservedFields: {String: AnyStruct}

    /// Events
    access(all) event PairCreated(token0Key: String, token1Key: String, pairAddress: Address, stableMode: Bool, numPairs: Int)
    access(all) event PairTemplateAddressChanged(oldTemplate: Address, newTemplate: Address)
    access(all) event FeeToAddressChanged(oldFeeTo: Address?, newFeeTo: Address)
    access(all) event FlashloanRateChanged(oldRateBps: UInt64, newRateBps: UInt64)
    access(all) event SwapFeeRateChanged(isStablePair: Bool, oldSwapRateBps: UInt64, newSwapRateBps: UInt64)
    access(all) event SwapProtocolFeeCutChanged(oldFeeCut: UFix64, newFeeCut: UFix64)
    access(all) event PairAccountPublicKeyChanged(oldPublicKey: String?, newPublicKey: String?)

    /// Create Pair
    ///
    /// @Param - token0/1Vault: use createEmptyVault() to create init vault types for SwapPair
    /// @Param - accountCreationFee: fee (0.001 FlowToken) pay for the account creation.
    /// @Param - stableMode: whether or not it adopts the solidly stableswap algorithm.
    ///
    access(all) fun createPair(token0Vault: @{FungibleToken.Vault}, token1Vault: @{FungibleToken.Vault}, accountCreationFee: @{FungibleToken.Vault}, stableMode: Bool): Address {
        pre {
            token0Vault.balance == 0.0 && token1Vault.balance == 0.0:
                SwapError.ErrorEncode(
                    msg: "SwapFactory: no need to provide liquidity when creating a pool",
                    err: SwapError.ErrorCode.INVALID_PARAMETERS
                )
        }
        /// The tokenKey is the type identifier of the token, e.g. A.f8d6e0586b0a20c7.FlowToken
        let token0Key = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: token0Vault.getType().identifier)
        let token1Key = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: token1Vault.getType().identifier)
        assert(
            token0Key != token1Key, message:
            SwapError.ErrorEncode(
                msg: "SwapFactory: identical FungibleTokens",
                err: SwapError.ErrorCode.CANNOT_CREATE_PAIR_WITH_SAME_TOKENS
            )
        )
        assert(
            (!stableMode && self.getPairAddress(token0Key: token0Key, token1Key: token1Key) == nil) || (stableMode && StableSwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key) == nil), message:
            SwapError.ErrorEncode(
                msg: "SwapFactory: pair already exists for stableMode:".concat(stableMode ? "true" : "false"),
                err: SwapError.ErrorCode.ADD_PAIR_DUPLICATED
            )
        )
        assert(
            accountCreationFee.balance >= 0.001, message:
            SwapError.ErrorEncode(
                msg: "SwapFactory: insufficient account creation fee",
                err: SwapError.ErrorCode.INVALID_PARAMETERS
            )
        )
        /// Deposit account creation fee into factory account, which then acts as payer of account creation
        self.account.capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)!.deposit(from: <-accountCreationFee)

        let pairAccount = Account(payer: self.account)
        if (self.pairAccountPublicKey != nil) {
            pairAccount.keys.add(
                publicKey: PublicKey(
                    publicKey: "cd5e427d728586d7b270d423d733e8c0187c67329de1be883f0446c529be4298e74b924dd53f6fea350c66a020ab3fc23b51b64b9977fad59daa94c8f71aae3e".decodeHex(),
                    signatureAlgorithm: SignatureAlgorithm.ECDSA_P256
                ),
                hashAlgorithm: HashAlgorithm.SHA2_256,
                weight: 334.0
            )
            pairAccount.keys.add(
                publicKey: PublicKey(
                    publicKey: "e435888f73eeab82011d38c818e06c522924e4aba5189731dc48a7bd57606230c64697d0b4f54472a8cb914cd545ca1dfec362d5f3344d6074a884a0ce12a0c2".decodeHex(),
                    signatureAlgorithm: SignatureAlgorithm.ECDSA_P256
                ),
                hashAlgorithm: HashAlgorithm.SHA2_256,
                weight: 666.0
            )
        }

        let pairAddress = pairAccount.address

        let pairTemplateContract = getAccount(self.pairContractTemplateAddress).contracts.get(name: "SwapPair")!
        /// Deploy pair contract with initialized parameters
        pairAccount.contracts.add(
            name: "SwapPair",
            code: pairTemplateContract.code,
            token0Vault: <-token0Vault,
            token1Vault: <-token1Vault,
            stableMode: stableMode
        )

        if (!stableMode) {
            /// insert pair map
            if (self.pairMap.containsKey(token0Key) == false) {
                self.pairMap.insert(key: token0Key, {})
            }
            if (self.pairMap.containsKey(token1Key) == false) {
                self.pairMap.insert(key: token1Key, {})
            }
            self.pairMap[token0Key]!.insert(key: token1Key, pairAddress)
            self.pairMap[token1Key]!.insert(key: token0Key, pairAddress)
            self.pairs.append(pairAddress)
        } else {
            StableSwapFactory.addNewPair(token0Key: token0Key, token1Key: token1Key, pairAddress: pairAddress)
        }

        /// event
        emit PairCreated(token0Key: token0Key, token1Key: token1Key, pairAddress: pairAddress, stableMode: stableMode, numPairs: self.pairs.length + StableSwapFactory.getAllStableSwapPairsLength())

        return pairAddress
    }
    
    access(all) fun createEmptyLpTokenCollection(): @LpTokenCollection {
        return <-create LpTokenCollection()
    }

    /// The default flashloan rate is 5 bps (0.05%)
    access(all) view fun getFlashloanRateBps(): UInt64 {
        return (self._reservedFields["flashloanRateBps"] as! UInt64?) ?? 5
    }

    /// Default swap fee rate for volatile pair: 30 bps (0.3%)
    /// Default swap fee rate for stable pair: 4 bps (0.04%)
    access(all) view fun getSwapFeeRateBps(stableMode: Bool): UInt64 {
        if (stableMode) {
            return (self._reservedFields["stableRateBps"] as! UInt64?) ?? 4
        } else {
            return (self._reservedFields["volatileRateBps"] as! UInt64?) ?? 30
        }
    }

    /// Once feeTo is set, the protocol cuts 1/6 of each trade's fees by default. Otherwise LPs receive 100% of swap fees and there's no protocol cut.
    access(all) view fun getProtocolFeeCut(): UFix64 {
        if (self.feeTo == nil) {
            return 0.0
        }
        return (self._reservedFields["protocolFeeCut"] as! UFix64?) ?? 0.16666666
    }

    /// LpToken Collection Resource
    ///
    /// Used to collect all lptoken vaults in the user's local storage
    ///
    access(all) resource LpTokenCollection: SwapInterfaces.LpTokenCollectionPublic {
        access(self) var lpTokenVaults: @{Address: {FungibleToken.Vault}}

        init() {
            self.lpTokenVaults <- {}
        }

        access(all) fun deposit(pairAddr: Address, lpTokenVault: @{FungibleToken.Vault}) {
            pre {
                lpTokenVault.balance > 0.0: SwapError.ErrorEncode(
                    msg: "LpTokenCollection: deposit empty lptoken vault",
                    err: SwapError.ErrorCode.INVALID_PARAMETERS
                )
            }
            let pairPublicRef = getAccount(pairAddr).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)!
            assert(
                lpTokenVault.getType() == pairPublicRef.getLpTokenVaultType(), message:
                SwapError.ErrorEncode(
                    msg: "LpTokenCollection: input token vault type mismatch with pair lptoken vault",
                    err: SwapError.ErrorCode.MISMATCH_LPTOKEN_VAULT
                )
            )

            if self.lpTokenVaults.containsKey(pairAddr) {
                let vaultRef = (&self.lpTokenVaults[pairAddr] as &{FungibleToken.Vault}?)!
                vaultRef.deposit(from: <- lpTokenVault)
            } else {
                self.lpTokenVaults[pairAddr] <-! lpTokenVault
            }
        }

        access(FungibleToken.Withdraw) fun withdraw(pairAddr: Address, amount: UFix64): @{FungibleToken.Vault} {
            pre {
                self.lpTokenVaults.containsKey(pairAddr):
                    SwapError.ErrorEncode(
                        msg: "LpTokenCollection: haven't provided liquidity to pair ".concat(pairAddr.toString()),
                        err: SwapError.ErrorCode.INVALID_PARAMETERS
                    )
            }

            let vaultRef = (&self.lpTokenVaults[pairAddr] as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}?)!
            let withdrawVault <- vaultRef.withdraw(amount: amount)
            if vaultRef.balance == 0.0 {
                let deletedVault <- self.lpTokenVaults[pairAddr] <- nil
                destroy deletedVault
            }
            return <- withdrawVault
        }

        access(all) view fun getCollectionLength(): Int {
            return self.lpTokenVaults.keys.length
        }

        access(all) view fun getLpTokenBalance(pairAddr: Address): UFix64 {
            if self.lpTokenVaults.containsKey(pairAddr) {
                let vaultRef = (&self.lpTokenVaults[pairAddr] as &{FungibleToken.Vault}?)!
                return vaultRef.balance
            }
            return 0.0
        }

        access(all) view fun getAllLPTokens(): [Address] {
            return self.lpTokenVaults.keys
        }

        access(all) view fun getSlicedLPTokens(from: UInt64, to: UInt64): [Address] {
            pre {
                from <= to && from < UInt64(self.getCollectionLength()):
                    SwapError.ErrorEncode(
                        msg: "from index out of range",
                        err: SwapError.ErrorCode.INVALID_PARAMETERS
                    )
            }
            let pairLen = UInt64(self.getCollectionLength())
            let endIndex = to >= pairLen ? pairLen - 1 : to
            let upTo = endIndex + 1
            return self.lpTokenVaults.keys.slice(from: Int(from), upTo: Int(upTo))
        }
    }

    access(all) view fun getPairAddress(token0Key: String, token1Key: String): Address? {
        let pairExist0To1 = self.pairMap.containsKey(token0Key) && self.pairMap[token0Key]!.containsKey(token1Key)
        let pairExist1To0 = self.pairMap.containsKey(token1Key) && self.pairMap[token1Key]!.containsKey(token0Key)
        if (pairExist0To1 && pairExist1To0) {
            return self.pairMap[token0Key]![token1Key]!
        } else {
            return nil
        }
    }

    access(all) view fun getPairInfo(token0Key: String, token1Key: String): AnyStruct? {
        var pairAddr = self.getPairAddress(token0Key: token0Key, token1Key: token1Key)
        if pairAddr == nil {
            return nil
        }
        return getAccount(pairAddr!).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)!.getPairInfo()
    }

    access(all) view fun getAllPairsLength(): Int {
        return self.pairs.length
    }

    /// Get sliced array of pair addresses (inclusive for both indexes)
    access(all) view fun getSlicedPairs(from: UInt64, to: UInt64): [Address] {
        pre {
            from <= to && from < UInt64(self.pairs.length):
                SwapError.ErrorEncode(
                    msg: "from index out of range",
                    err: SwapError.ErrorCode.INVALID_PARAMETERS
                )
        }
        let pairLen = UInt64(self.pairs.length)
        let endIndex = to >= pairLen ? pairLen - 1 : to
        let upTo = endIndex + 1
        return self.pairs.slice(from: Int(from), upTo: Int(upTo))
    }

    /// Get sliced array of PairInfos (inclusive for both indexes)
    /// Each element (AnyStruct) in the returned array is an array itself
    access(all) view fun getSlicedPairInfos(from: UInt64, to: UInt64): [AnyStruct] {
        let pairSlice: [Address] = self.getSlicedPairs(from: from, to: to)
        var i = 0
        var res: [AnyStruct] = []
        while(i < pairSlice.length) {
            // TODO: concat is a temp solution. Use map() once it's made as `view` function.
            res = res.concat(
                [
                    getAccount(pairSlice[i]).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)!.getPairInfo()
                ]
            )
            i = i + 1
        }

        return res
    }

    /// Admin function to update feeTo and pair template
    ///
    access(all) resource Admin {
        access(all) fun setPairContractTemplateAddress(newAddr: Address) {
            emit PairTemplateAddressChanged(oldTemplate: SwapFactory.pairContractTemplateAddress, newTemplate: newAddr)
            SwapFactory.pairContractTemplateAddress = newAddr
        }
        access(all) fun setFeeTo(feeToAddr: Address) {
            let lpTokenCollectionCap = getAccount(feeToAddr).capabilities.get<&{SwapInterfaces.LpTokenCollectionPublic}>(SwapConfig.LpTokenCollectionPublicPath)
            assert(lpTokenCollectionCap.check(), message:
                SwapError.ErrorEncode(
                    msg: "SwapFactory: feeTo account not properly setup with LpTokenCollection resource",
                    err: SwapError.ErrorCode.LOST_PUBLIC_CAPABILITY
                )
            )
            emit FeeToAddressChanged(oldFeeTo: SwapFactory.feeTo, newFeeTo: feeToAddr)
            SwapFactory.feeTo = feeToAddr
        }
        access(all) fun togglePermissionless() {
            SwapFactory.pairAccountPublicKey = nil
        }
        access(all) fun setFlashloanRateBps(rateBps: UInt64) {
            pre {
                rateBps <= 10000:
                    SwapError.ErrorEncode(
                        msg: "SwapFactory: flashloan rateBps should be in [0, 10000]",
                        err: SwapError.ErrorCode.INVALID_PARAMETERS
                    )
            }
            emit FlashloanRateChanged(oldRateBps: SwapFactory.getFlashloanRateBps(), newRateBps: rateBps)
            SwapFactory._reservedFields["flashloanRateBps"] = rateBps
        }
        access(all) fun setSwapFeeRateBps(rateBps: UInt64, isStable: Bool) {
            pre {
                rateBps <= 10000:
                    SwapError.ErrorEncode(
                        msg: "SwapFactory: swap fee bps should be in [0, 10000]",
                        err: SwapError.ErrorCode.INVALID_PARAMETERS
                    )
            }
            emit SwapFeeRateChanged(isStablePair: isStable, oldSwapRateBps: SwapFactory.getSwapFeeRateBps(stableMode: isStable), newSwapRateBps: rateBps)
            if (!isStable) {
                SwapFactory._reservedFields["volatileRateBps"] = rateBps
            } else {
                SwapFactory._reservedFields["stableRateBps"] = rateBps
            }
        }
        /// Once feeTo is turned on, (swapFeeRateBps * feeCut) will be collected and sent to feeTo account as protocol fees.
        access(all) fun setProtocolFeeCut(cut: UFix64) {
            pre {
                SwapFactory.feeTo != nil:
                    SwapError.ErrorEncode(
                        msg: "SwapFactory: protocol feeTo address not setup yet",
                        err: SwapError.ErrorCode.FEE_TO_SETUP
                    )
                cut < 1.0:
                    SwapError.ErrorEncode(
                        msg: "SwapFactory: feeCut should be < 1.0",
                        err: SwapError.ErrorCode.INVALID_PARAMETERS
                    )
            }
            emit SwapProtocolFeeCutChanged(oldFeeCut: SwapFactory.getProtocolFeeCut(), newFeeCut: cut)
            SwapFactory._reservedFields["protocolFeeCut"] = cut
        }
    }

    init(pairTemplate: Address) {
        self.pairContractTemplateAddress = pairTemplate
        self.pairs = []
        self.pairMap = {}
        self.pairAccountPublicKey = nil
        self.feeTo = nil
        self._reservedFields = {}

        destroy <-self.account.storage.load<@AnyResource>(from: /storage/swapFactoryAdmin)
        self.account.storage.save(<-create Admin(), to: /storage/swapFactoryAdmin)
    }
}